#!/usr/bin/env bash
# ssh_remote_xdg_open.sh
# Have remote ssh session open URLs with xdg-open in your local web browser.
# Uses: socat, systemd --user, ssh
#
# Usage (do these steps in order):
#   ssh_remote_xdg_open.sh install-local            # create and enable local systemd socket+service
#   ssh_remote_xdg_open.sh enable-socket            # enable+start local socket
#   ssh_remote_xdg_open.sh configure-ssh <host>     # append RemoteForward block to ~/.ssh/config (local)
#   ssh_remote_xdg_open.sh install-remote <host>    # copy remote helper(s) to <host> (ssh target)
#   ssh_remote_xdg_open.sh test <host>              # quick smoke test (requires ssh session)
#
# Other useful commands:
#   ssh_remote_xdg_open.sh disable-socket           # stop+disable local socket
#   ssh_remote_xdg_open.sh remove-remote  <host>    # remove injected files on remote
#   ssh_remote_xdg_open.sh uninstall-local          # remove local unit files (and stop socket)
#   ssh_remote_xdg_open.sh status                   # show overall status (socket + recent logs)
#   ssh_remote_xdg_open.sh status-socket            # show systemctl status for the socket
#   ssh_remote_xdg_open.sh status-service           # show active service instances (if any)
#   ssh_remote_xdg_open.sh logs [--since -1h]       # show recent journal for socket/service
#   ssh_remote_xdg_open.sh help
#
# Notes:
#  - Run this on your workstation (where you want the browser to open).
#  - It will inject scripts into the remote host using SSH + heredoc.
#  - Defaults:
#      remote TCP port: 19999
#      local socket:   $XDG_RUNTIME_DIR/ssh_remote_xdg_open.sock  (falls back to /run/user/$UID/ssh_remote_xdg_open.sock)
#  - Requires `socat` on local machine and (on remote) `socat` if you want the helper to use it.
#  - The script is conservative and idempotent where reasonable.
set -Eeuo pipefail

# --- configuration defaults ---
PORT_DEFAULT=19999
SOCKET_PATH_DEFAULT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh_remote_xdg_open.sock"
SSH_CONFIG_PATH="${HOME}/.ssh/config"

# name/location of injected remote helper
REMOTE_BIN_DIR="${HOME}/.local/bin"
REMOTE_OPEN_LOCAL="${REMOTE_BIN_DIR}/open-local"
REMOTE_XDG_SHIM="${REMOTE_BIN_DIR}/xdg-open"

# local handler script
LOCAL_BIN_DIR="${HOME}/.local/bin"
LOCAL_HANDLER="${LOCAL_BIN_DIR}/ssh-remote-xdg-open-handler"

# systemd unit filenames
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SOCKET_UNIT_NAME="ssh_remote_xdg_open.socket"
SERVICE_UNIT_NAME="ssh_remote_xdg_open@.service"

# --- helper functions ---
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
}

ensure_dir() {
  mkdir -p -- "$1"
}

local_socket_path() {
  printf '%s' "${SSH_OPENURL_SOCKET:-$SOCKET_PATH_DEFAULT}"
}

# Write the local handler script
write_local_handler() {
  ensure_dir "$LOCAL_BIN_DIR"

  info "Writing local handler to $LOCAL_HANDLER"
  cat > "$LOCAL_HANDLER" <<'HANDLER_EOF'
#!/bin/sh
# ssh-remote-xdg-open-handler
# Reads NUL-delimited "host\turl" messages from stdin.
# For localhost URLs, sets up an SSH local port forward via control socket
# and rewrites the URL to a deterministic 127.x.x.x address.
set -eu

# Hash a string to a deterministic 127.x.x.x address (avoiding 127.0.0.1)
host_to_loopback() {
  _alias="$1"
  _hash=$(printf '%s' "$_alias" | cksum | cut -d' ' -f1)
  _b1=$(( (_hash >> 16) % 254 + 1 ))  # 1-254
  _b2=$(( (_hash >> 8)  % 256 ))      # 0-255
  _b3=$(( _hash         % 254 + 1 ))  # 1-254 (avoid .0)
  # Avoid 127.0.0.1
  if [ "$_b1" -eq 0 ] && [ "$_b2" -eq 0 ] && [ "$_b3" -eq 1 ]; then
    _b3=2
  fi
  printf '127.%d.%d.%d' "$_b1" "$_b2" "$_b3"
}

# Extract scheme, host, port, and path from a URL
parse_url() {
  _url="$1"
  URL_SCHEME="${_url%%://*}"
  _rest="${_url#*://}"
  _hostport="${_rest%%/*}"
  URL_PATH="/${_rest#*/}"
  # Handle URLs with no path (e.g., http://localhost:8080)
  case "$_rest" in
    */*) URL_PATH="/${_rest#*/}" ;;
    *)   URL_PATH="" ;;
  esac
  # Split host:port
  case "$_hostport" in
    *:*) URL_HOST="${_hostport%%:*}"; URL_PORT="${_hostport##*:}" ;;
    *)   URL_HOST="$_hostport"; URL_PORT="" ;;
  esac
}

# Check if a host is localhost
is_localhost() {
  case "$1" in
    localhost|127.0.0.1|"[::1]"|::1) return 0 ;;
    *) return 1 ;;
  esac
}

# Try to set up an SSH local port forward via control socket
setup_forward() {
  _ssh_host="$1"
  _local_addr="$2"
  _port="$3"
  # -O forward uses the existing multiplexed connection
  ssh -O forward -L "${_local_addr}:${_port}:localhost:${_port}" "$_ssh_host" 2>/dev/null || true
}

# Process a single host\turl message
handle_message() {
  _msg="$1"
  # Split on tab
  _host_alias="${_msg%%	*}"
  _url="${_msg#*	}"

  # If no tab was found (backwards compat: bare URL), just open it
  if [ "$_host_alias" = "$_url" ]; then
    xdg-open "$_url"
    return
  fi

  parse_url "$_url"

  if is_localhost "$URL_HOST" && [ -n "$URL_PORT" ] && [ -n "$_host_alias" ]; then
    _local_addr=$(host_to_loopback "$_host_alias")
    setup_forward "$_host_alias" "$_local_addr" "$URL_PORT"
    _new_url="${URL_SCHEME}://${_local_addr}:${URL_PORT}${URL_PATH}"
    xdg-open "$_new_url"
  else
    xdg-open "$_url"
  fi
}

# Read NUL-delimited messages from stdin
# Using tr to convert NUL to newline, then process line by line
tr '\0' '\n' | while IFS= read -r msg; do
  [ -z "$msg" ] && continue
  handle_message "$msg"
done
HANDLER_EOF

  chmod +x "$LOCAL_HANDLER"
  info "Handler installed."
}

# Write local user systemd units
write_systemd_units() {
  local socket_path
  socket_path="$(local_socket_path)"

  ensure_dir "$SYSTEMD_USER_DIR"

  local socket_file="$SYSTEMD_USER_DIR/$SOCKET_UNIT_NAME"
  local service_file="$SYSTEMD_USER_DIR/$SERVICE_UNIT_NAME"

  info "Writing systemd user socket to $socket_file"
  cat > "$socket_file" <<EOF
[Unit]
Description=Local "open URL" socket for ssh-openurl

[Socket]
ListenStream=$socket_path
SocketMode=0600
Accept=yes

[Install]
WantedBy=default.target
EOF

  info "Writing systemd user service to $service_file"
  cat > "$service_file" <<EOF
[Unit]
Description=Local "open URL" service instance

[Service]
# Read NUL-separated host\\turl messages from socket and handle them.
# The handler sets up SSH port forwards for localhost URLs.
ExecStart=/bin/sh -lc '${LOCAL_HANDLER}'
StandardInput=socket
EOF

  info "Reloading user systemd daemon"
  systemctl --user daemon-reload
  info "Done writing units."
}

enable_socket() {
  write_systemd_units >/dev/null 2>&1 || true
  info "Enabling and starting $SOCKET_UNIT_NAME"
  systemctl --user enable --now "$SOCKET_UNIT_NAME"
  info "Socket enabled and started (if supported)."
}

disable_socket() {
  info "Stopping and disabling $SOCKET_UNIT_NAME"
  systemctl --user stop "$SOCKET_UNIT_NAME" || true
  systemctl --user disable "$SOCKET_UNIT_NAME" || true
  info "Done."
}

uninstall_local() {
  disable_socket
  info "Removing systemd unit files"
  rm -f -- "$SYSTEMD_USER_DIR/$SOCKET_UNIT_NAME" "$SYSTEMD_USER_DIR/$SERVICE_UNIT_NAME"
  systemctl --user daemon-reload
  info "Removing local handler"
  rm -f -- "$LOCAL_HANDLER"
  info "Removed."
}

# Add RemoteForward block to ~/.ssh/config (idempotent)
configure_ssh() {
  local remote_host="$1"
  local socket_path remote_port cfg tmp managed_tag want_rf want_eo
  socket_path="$(local_socket_path)"
  remote_port="${SSH_OPENURL_PORT:-$PORT_DEFAULT}"
  cfg="${SSH_CONFIG_PATH}"
  tmp="${cfg}.tmp"
  managed_tag="# ssh_remote_xdg_open: managed"

  ensure_dir "$(dirname "$cfg")"
  touch "$cfg" || die "cannot create $cfg"
  chmod 600 "$cfg" || true

  want_rf="RemoteForward 127.0.0.1:${remote_port} ${socket_path}"
  want_eo="ExitOnForwardFailure yes"
  want_cm="ControlMaster auto"
  want_cp="ControlPath ~/.ssh/sockets/%r@%h-%p"
  want_cps="ControlPersist 10m"

  # Ensure the control socket directory exists
  ensure_dir "${HOME}/.ssh/sockets"

  # Merge/update while preserving formatting. We:
  #  - Find exact "Host <remote_host>" stanza.
  #  - Insert our managed lines immediately after the Host line.
  #  - Indent with the first directive indent of the stanza if present, else 2 spaces.
  #  - Move leading blank/comment lines to *after* our insert.
  #  - Skip any old managed lines elsewhere in the stanza.
  awk -v tgt="$remote_host" \
      -v rf="$want_rf" -v eo="$want_eo" \
      -v cm="$want_cm" -v cp="$want_cp" -v cps="$want_cps" \
      -v tag="$managed_tag" '
    function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
    function leadws(s,   m){ if (match(s, /^[ \t]*/)) return substr(s,1,RLENGTH); return "" }
    function is_managed(s){ return (s ~ /[ \t]*#[ \t]*ssh_remote_xdg_open: managed[ \t]*$/) }

    BEGIN{
      in_tgt=0; saw_any=0; inserted=0; indent="  "
      bufN=0; preN=0; last_nonempty=1
    }

    # Flush buffered Host line + (optional) our inserts + pre-buffer lines
    function flush_buffer(){
      if (bufN>0){
        for(i=1;i<=bufN;i++) print buf[i]
        bufN=0
      }
      if (in_tgt && !inserted){
        # insert our managed lines right after Host line
        print indent rf "  " tag
        print indent eo "  " tag
        print indent cm "  " tag
        print indent cp "  " tag
        print indent cps "  " tag
        inserted=1
        # then print preserved pre-buffer (blanks/comments that originally followed Host)
        for(i=1;i<=preN;i++) print pre[i]
        preN=0
      }
    }

    # Leaving a target stanza: ensure we inserted; reset state
    function close_tgt(){
      if (in_tgt){
        flush_buffer()
      }
      in_tgt=0; inserted=0; preN=0; indent="  "
    }

    {
      raw=$0
      line=raw
      ltrim(line)

      if (line ~ /^Host[ \t]+/){
        # starting a new stanza: close previous
        close_tgt()

        # parse host patterns
        pat=line
        sub(/^Host[ \t]+/,"",pat)
        n=split(pat, arr, /[ \t]+/)
        exact = (n==1 && arr[1]==tgt)

        # print new Host line later (buffer), so we can inject right after it
        buf[++bufN]=raw
        in_tgt = exact
        if (exact) { saw_any=1; inserted=0; preN=0; indent="  " }
        next
      }

      if (in_tgt){
        # If not yet inserted, figure out indentation on first real directive
        if (!inserted){
          # skip our own (old) managed lines
          if (is_managed(raw)) next

          # classify the line
          if (line=="" || line ~ /^#/){
            # Preserve, but it will be printed *after* our insert
            pre[++preN]=raw
            next
          } else {
            # First real directive: adopt its indent and flush Host + inserts, then print this line
            indent = leadws(raw)
            flush_buffer()
            print raw
            next
          }
        } else {
          # Already inserted; just skip any old managed lines and pass others
          if (is_managed(raw)) next
          print raw
          next
        }
      }

      # Not in target stanza: if we had a buffered Host (non-target), flush it now
      if (bufN>0){ flush_buffer() }
      print raw
      last_nonempty = (raw != "")
    }

    END{
      # File ended: close any open stanza
      if (bufN>0 || in_tgt){ flush_buffer() }

      if (!saw_any){
        # Append a dedicated Host block; avoid double blank line
        if (last_nonempty) print ""
        print "Host " tgt
        print "  " rf "  " tag
        print "  " eo "  " tag
        print "  " cm "  " tag
        print "  " cp "  " tag
        print "  " cps "  " tag
      }
    }
  ' "$cfg" > "$tmp" || die "awk merge failed; SSH config unchanged"

  mv "$tmp" "$cfg" || die "could not write merged SSH config to $cfg"

  info "Updated SSH config for host '${remote_host}' at: $cfg"
  info "→ RemoteForward set to 127.0.0.1:${remote_port} -> ${socket_path}"
  info "→ ControlMaster enabled (socket: ~/.ssh/sockets/)"
}

# Simple smoke test: connect via ssh and call open-local to see if it reaches local socket
test_roundtrip() {
  local remote="$1"
  local test_url="${2:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"
  local port="${SSH_OPENURL_PORT:-$PORT_DEFAULT}"

  info "Testing roundtrip: will call open-local on remote -> should trigger local xdg-open"
  info "Hint: ensure the local socket is active: systemctl --user status $SOCKET_UNIT_NAME"
  info "Opening ${test_url}"
  
  # Use the remote's $HOME path at runtime, not a locally-expanded path.
  # Also run via a login shell so PATH/env behave like your normal session.
  ssh "$remote" '${SHELL:-sh} -lc "OPEN_LOCAL_PORT='"$port"' \"\$HOME/.local/bin/open-local\" \"'"$test_url"'\""'

  info "If nothing opened locally, check:"
  info "  1) Local socket active: systemctl --user status $SOCKET_UNIT_NAME"
  info "  2) SSH reverse forward present: ssh -G $remote | sed -n \"s/^remoteforward //p\""
  info "  3) socat installed on remote (already checked during install)"
}

# -------- NEW: status helpers --------
_status_overview() {
  local sock_path; sock_path="$(local_socket_path)"
  echo "=== ssh_remote_xdg_open: status overview ==="
  echo "Socket path: $sock_path"
  if [[ -S "$sock_path" ]]; then
    echo "Socket exists: yes"
    ls -l "$sock_path"
  else
    echo "Socket exists: no"
  fi
  echo
  echo "— systemctl (socket) —"
  systemctl --user status "$SOCKET_UNIT_NAME" --no-pager || true
  echo
  echo "— active service instances —"
  systemctl --user list-units --type=service --all | grep -E "ssh_remote_xdg_open@\.service" || echo "(none active)"
  echo
  echo "— recent logs (last hour) —"
  journalctl --user -u "$SOCKET_UNIT_NAME" -u "$SERVICE_UNIT_NAME" --since -1h --no-pager || true
}

_status_socket() {
  systemctl --user status "$SOCKET_UNIT_NAME" --no-pager
}

_status_service() {
  # Show any active or recently run instances
  systemctl --user list-units --type=service --all | grep -E "ssh_remote_xdg_open@\.service" || true
  echo
  echo "Tip: use 'logs' to see journal entries for spawned instances."
}

_logs() {
  local since="${1:---since -1h}"
  # If user passed multiple args (e.g. --since 'today'), keep them
  if [[ "$since" == "--since" ]]; then
    shift || true
    since="--since ${1:-"-1h"}"
    shift || true
  fi
  journalctl --user -u "$SOCKET_UNIT_NAME" -u "$SERVICE_UNIT_NAME" $since --no-pager
}
# ------------------------------------

# Print usage
usage() {
  cat <<EOF
ssh_remote_xdg_open.sh - local installer for "open remote URL on local desktop"

Commands:
  install-local
      Create systemd user socket+service units and enable/start the socket.

  enable-socket
      Enable and start the user socket.

  disable-socket
      Stop and disable the user socket.

  uninstall-local
      Stop socket and remove local unit files.

  install-remote <ssh-target>
      Inject remote helpers (open-local, optional xdg-open shim) into the SSH target.

  remove-remote <ssh-target>
      Remove the injected files on the remote.

  configure-ssh <ssh-target>
      Append RemoteForward and ControlMaster blocks to your local ~/.ssh/config.

  test <ssh-target>
      Quick smoke test that calls open-local on the remote (requires SSH with forwarded port active).

  status
      Overview: socket status, any active service instances, recent logs.

  status-socket
      Focused systemctl status of the socket unit.

  status-service
      List any active or recent service instances (socket-activated).

  logs [--since -1h]
      Show recent logs for the socket and service units. Example: 'logs --since today'

Environment variables:
  SSH_OPENURL_PORT     Remote TCP port on remote host (default: $PORT_DEFAULT)
  SSH_OPENURL_SOCKET   Local socket path (default: $SOCKET_PATH_DEFAULT)
EOF
}

install_remote_helpers() {
  local remote="$1"
  require_cmd ssh

  # --- Preflight: socat must exist on the remote ---
  info "Preflight: checking for 'socat' on remote '$remote'…"
  if ! ssh "$remote" 'command -v socat >/dev/null 2>&1'; then
    die "Remote host '$remote' is missing 'socat'. Install it (apt/dnf/pacman/brew) and retry."
  fi

  info "Installing remote helper(s) to '$remote:~/.local/bin'"

  # Create remote bin dir and data dir with safe perms (expand on remote)
  ssh "$remote" 'mkdir -p "$HOME/.local/bin" "$HOME/.local/share/ssh_remote_xdg_open" && chmod 700 "$HOME/.local/bin"' \
    || die "Failed to create directories on remote"

  # Store the host alias so remote helpers can identify themselves to the local handler
  info "Storing host alias '$remote' on remote"
  ssh "$remote" "printf '%s' '$remote' > \"\$HOME/.local/share/ssh_remote_xdg_open/host_alias\""

  # ---- open-local ----
  info "Uploading open-local to remote"
  ssh "$remote" 'cat > "$HOME/.local/bin/open-local" && chmod +x "$HOME/.local/bin/open-local"' <<'REMOTE_OPEN_LOCAL_EOF'
#!/bin/sh
# Send NUL-delimited host\turl messages to the forwarded TCP port on the remote,
# which sshd will forward back to the local UNIX socket.
set -eu

PORT="${OPEN_LOCAL_PORT:-19999}"
HOST="127.0.0.1"
ALIAS_FILE="$HOME/.local/share/ssh_remote_xdg_open/host_alias"
HOST_ALIAS=""
if [ -f "$ALIAS_FILE" ]; then
  HOST_ALIAS=$(cat "$ALIAS_FILE")
fi

if [ $# -eq 0 ]; then
  echo "Usage: open-local <url> [more-urls...]" >&2
  exit 2
fi

{
  for url in "$@"; do
    printf '%s\t%s\0' "$HOST_ALIAS" "$url"
  done
} | socat - "TCP:${HOST}:${PORT}",connect-timeout=3
REMOTE_OPEN_LOCAL_EOF

  # ---- xdg-open shim ----
  info "Uploading xdg-open shim to remote (~/.local/bin/xdg-open)"
  ssh "$remote" 'cat > "$HOME/.local/bin/xdg-open" && chmod +x "$HOME/.local/bin/xdg-open"' <<'REMOTE_XDG_SHIM_EOF'
#!/bin/sh
# Prefer the SSH reverse-forward to open URLs locally; otherwise use a native opener.
set -eu

PORT="${OPEN_LOCAL_PORT:-19999}"
ALIAS_FILE="$HOME/.local/share/ssh_remote_xdg_open/host_alias"
HOST_ALIAS=""
if [ -f "$ALIAS_FILE" ]; then
  HOST_ALIAS=$(cat "$ALIAS_FILE")
fi

# Choose a native opener on the remote (Linux/macOS)
if command -v xdg-open >/dev/null 2>&1; then
  FALLBACK_OPENER="xdg-open"
elif command -v open >/dev/null 2>&1; then
  FALLBACK_OPENER="open"
else
  FALLBACK_OPENER="/usr/bin/xdg-open"
fi

# If the tunnel is reachable, ship NUL-delimited host\turl messages through it.
if socat -u - "TCP:127.0.0.1:${PORT}",connect-timeout=3 </dev/null >/dev/null 2>&1; then
  {
    for url in "$@"; do
      printf '%s\t%s\0' "$HOST_ALIAS" "$url"
    done
  } | socat - "TCP:127.0.0.1:${PORT}" || exit $?
else
  exec "$FALLBACK_OPENER" "$@"
fi
REMOTE_XDG_SHIM_EOF

  # ---- Post-install: static guidance (no PATH probing) ----
  info "Remote helpers installed."
  info "To ensure programs on the remote use the shim by default, add this to your remote shell config:"
  echo '  # Bash:'
  echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc'
  echo '  # Zsh:'
  echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc'
  echo
  info "For non-interactive SSH commands, add to ~/.ssh/rc on the remote:"
  echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.ssh/rc && chmod 700 ~/.ssh/rc'
  echo
  info "Done."
}

remove_remote_helpers() {
  local remote="$1"
  info "Removing remote helper(s) from $remote"
  ssh "$remote" 'rm -f "$HOME/.local/bin/open-local" "$HOME/.local/bin/xdg-open" || true; rm -rf "$HOME/.local/share/ssh_remote_xdg_open" || true'
  info "Done."
}

# --- entrypoint ---
if [ $# -lt 1 ]; then usage; exit 1; fi

cmd="$1"; shift || true

case "$cmd" in
  help|-h|--help) usage ;;
  install-local)
    require_cmd systemctl
    require_cmd xdg-open
    require_cmd ssh
    if ! command -v socat >/dev/null 2>&1; then
      info "Warning: 'socat' not found locally. Remote helpers use socat; install it for best results."
    fi
    write_local_handler
    write_systemd_units
    enable_socket
    ;;
  enable-socket)
    require_cmd systemctl
    enable_socket
    ;;
  disable-socket)
    require_cmd systemctl
    disable_socket
    ;;
  uninstall-local)
    uninstall_local
    ;;
  install-remote)
    [ $# -ge 1 ] || die "install-remote requires <ssh-target>"
    install_remote_helpers "$1"
    ;;
  remove-remote)
    [ $# -ge 1 ] || die "remove-remote requires <ssh-target>"
    remove_remote_helpers "$1"
    ;;
  configure-ssh)
    [ $# -ge 1 ] || die "configure-ssh requires <ssh-target>"
    configure_ssh "$1"
    ;;
  test)
    [ $# -ge 1 ] || die "test requires <ssh-target>"
    test_roundtrip "$1" "${2:-}"
    ;;
  status)
    _status_overview
    ;;
  status-socket)
    _status_socket
    ;;
  status-service)
    _status_service
    ;;
  logs)
    _logs "$@"
    ;;
  *)
    die "Unknown command: $cmd (try 'help')"
    ;;
esac
