#!/usr/bin/env bash
set -Eeuo pipefail

# === Settings ===
: "${XDG_CONFIG_HOME:="$HOME/.config"}"
RCLONE_CFG_DIR="$XDG_CONFIG_HOME/rclone"
MOUNT_POINTS_FILE="$RCLONE_CFG_DIR/mount_points.cfg"
SYSTEMD_USER_DIR="$XDG_CONFIG_HOME/systemd/user"

# Defaults for mount behavior (can be overridden via environment)
: "${RCLONE_VFS_CACHE_MODE:=writes}"
: "${RCLONE_DIR_CACHE_TIME:=5s}"

# === Helpers ===
_die() { echo "Error: $*" >&2; exit 1; }
_need() { command -v "$1" >/dev/null 2>&1 || _die "Required command '$1' not found"; }
_mkdirp() { mkdir -p "$1"; }

# Read mountpoint for a remote from ~/.config/rclone/mount_points.cfg
_get_mountpoint() {
  local name="$1"
  [[ -f "$MOUNT_POINTS_FILE" ]] || return 1
  # lines like: name=/path/to/mount
  awk -F= -v k="$name" '$1==k {print $2}' "$MOUNT_POINTS_FILE" | tail -n1
}

# Set/replace mountpoint entry
_set_mountpoint() {
  local name="$1" mp="$2"
  _mkdirp "$(dirname "$MOUNT_POINTS_FILE")"
  touch "$MOUNT_POINTS_FILE"
  # remove old line(s) for name
  grep -v -e "^${name}=" "$MOUNT_POINTS_FILE" > "${MOUNT_POINTS_FILE}.tmp" || true
  echo "${name}=${mp}" >> "${MOUNT_POINTS_FILE}.tmp"
  mv "${MOUNT_POINTS_FILE}.tmp" "$MOUNT_POINTS_FILE"
}

# Systemd unit filename for a remote
_unit_name() {
  local name="$1"
  # keep it simple; allow letters, digits, dash/underscore
  echo "rclone-${name}.service"
}

# Create (or overwrite) systemd --user unit for a remote
_write_unit() {
  local name="$1"
  local mp="$2"
  local unit="$(_unit_name "$name")"
  _mkdirp "$SYSTEMD_USER_DIR"
  cat > "${SYSTEMD_USER_DIR}/${unit}" <<EOF
[Unit]
Description=Mount ${name} via rclone
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# You can tweak these defaults via environment variables.
Environment=RCLONE_VFS_CACHE_MODE=${RCLONE_VFS_CACHE_MODE}
Environment=RCLONE_DIR_CACHE_TIME=${RCLONE_DIR_CACHE_TIME}
ExecStart=/usr/bin/rclone mount ${name}: ${mp}
ExecStop=/bin/fusermount -u ${mp}
Restart=on-failure

[Install]
WantedBy=default.target
EOF
}

_print_help() {
  cat <<'EOF'
Usage: rclone-webdav.sh <command> [args]

Commands:
  help                    Show this help text.
  config                  Interactive setup: creates/updates an rclone WebDAV remote
                          and saves its mount point in ~/.config/rclone/mount_points.cfg.
  mount <name>            Mount the remote now (foreground). Uses saved mount point.
  enable <name>           Install and enable a systemd --user service for the remote.
  disable <name>          Disable and stop the systemd --user service for the remote.
  uninstall <name>        Disable, stop, and remove the systemd --user service file.
  status <name>           Check status of the systemd unit.
  log <name>              Show log from the systemd unit.

Notes:
- TLS mTLS paths (client cert/key) are stored in rclone.conf via global.client_cert/global.client_key.
- Mount options default to RCLONE_VFS_CACHE_MODE="writes" and RCLONE_DIR_CACHE_TIME="5s".
  Override by exporting env vars before running, or edit the generated unit.
- Mount point paths are stored as entries in ~/.config/rclone/mount_points.cfg (format: NAME=/path).
EOF
}

_prompt_default() {
  local prompt="$1" default="${2:-}"
  local ans
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " ans || true
    echo "${ans:-$default}"
  else
    read -r -p "$prompt: " ans || true
    echo "$ans"
  fi
}

_prompt_secret() {
  local prompt="$1"
  local ans
  read -r -s -p "$prompt: " ans || true
  echo
  echo "$ans"
}

_cmd_config() {
  _need rclone
  echo "== Interactive rclone WebDAV setup (idempotent) =="

  local name url vendor user pass client_cert client_key mount_point

  # --- prompts ---
  name="$(_prompt_default 'Remote volume name (e.g., ryan-files)')"
  url="$(_prompt_default 'WebDAV URL (e.g., https://copyparty.example.com)')"
  vendor="$(_prompt_default 'Vendor (copyparty|owncloud|nextcloud|other)' 'copyparty')"
  user="$(_prompt_default 'Username (HTTP Auth; username ignored copyparty)')"
  pass="$(_prompt_secret 'Password (HTTP Auth)')"
  echo
  client_cert="$(_prompt_default 'Client certificate PEM path' "$HOME/.config/rclone/client.crt")"
  client_key="$(_prompt_default 'Client key PEM path' "$HOME/.config/rclone/client.key")"
  local mp_default="$(realpath $HOME/${name})"
  mount_point="$(_prompt_default 'Mount point (absolute)' "$mp_default")"

  # --- sanitize values to avoid CR/LF sneaking in ---
  sanitize() { printf %s "$1" | tr -d '\r\n'; }
  name=$(sanitize "$name"); url=$(sanitize "$url"); vendor=$(sanitize "$vendor")
  user=$(sanitize "$user"); pass=$(sanitize "$pass")
  client_cert=$(sanitize "$client_cert"); client_key=$(sanitize "$client_key")

  # vendor alias
  [[ "$vendor" == "copyparty" ]] && vendor="owncloud"

  echo
  echo "Creating/updating rclone remote '$name'..."

  # if exists, replace to keep idempotent
  if rclone config show 2>/dev/null | grep -qxF "[$name]"; then
    rclone config delete "$name" >/dev/null || true
  fi

  # build args array; only include user/pass if non-empty
  args=( "$name" webdav
         "url=$url" "vendor=$vendor" "pacer_min_sleep=0.01ms"
         "global.client_cert=$client_cert" "global.client_key=$client_key" )

  if [[ -n "$user" ]]; then
    args+=( "user=$user" )
  fi
  if [[ -n "$pass" ]]; then
    # use --obscure so rclone stores it safely
    rclone config create "${args[@]}" "pass=$pass" --obscure
  else
    rclone config create "${args[@]}"
  fi

  echo "Saving mount point mapping: ${name} -> ${mount_point}"
  _set_mountpoint "$name" "$mount_point"

  echo "Done. Try:"
  echo "  $(basename "$0") mount $name"
  echo "  $(basename "$0") enable $name"
}

_cmd_mount() {
  _need rclone
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 mount <name>"
  local mp="$(_get_mountpoint "$name")" || _die "No mount point stored for '$name'. Run '$0 config' first."

  # Ensure directory exists
  _mkdirp "$mp"
  echo "Temporarily mounting ${name}: at $mp"
  echo "This process will now block as it services the mount."
  echo "If you want to run in the background, you should enable the systemd unit instead."
  echo "e.g., \`${BASH_SOURCE} enable ${name}\`"
  exec rclone mount "${name}:" "$mp" \
    --vfs-cache-mode "$RCLONE_VFS_CACHE_MODE" \
    --dir-cache-time "$RCLONE_DIR_CACHE_TIME"
}

_cmd_enable() {
  _need systemctl
  _need rclone
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 enable <name>"
  local mp="$(_get_mountpoint "$name")" || _die "No mount point stored for '$name'. Run '$0 config' first."

  _write_unit "$name" "$mp"
  systemctl --user daemon-reload
  systemctl --user enable "$(_unit_name "$name")"
  echo "Enabled systemd/User service: $(_unit_name "$name")"
  systemctl --user start "$(_unit_name "$name")"
  echo "Started systemd/User service: $(_unit_name "$name")"
  echo "Waiting 5 seconds before checking status ..."
  sleep 5
  systemctl --user status "$(_unit_name "$name")"
}

_cmd_disable() {
  _need systemctl
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 disable <name>"
  local unit="$(_unit_name "$name")"
  systemctl --user disable "$unit" || true
  systemctl --user stop "$unit" || true
  systemctl --user daemon-reload
  systemctl --user status "$unit" || true
  echo
  echo "Disabled service: $unit."
  echo "Stopped service: $unit"
}

_cmd_uninstall() {
  _need systemctl
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 uninstall <name>"
  local unit="$(_unit_name "$name")"
  systemctl --user disable "$unit" || true
  systemctl --user stop "$unit" || true
  rm -f "${SYSTEMD_USER_DIR}/${unit}"
  systemctl --user daemon-reload
  systemctl --user status "$unit" || true
  echo
  echo "Removed ${unit}."
}

_cmd_status() {
  _need systemctl
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 status <name>"
  systemctl --user status "$(_unit_name "$name")"
}

_cmd_log() {
  _need journalctl
  local name="${1:-}"; [[ -n "$name" ]] || _die "Usage: $0 status <name>"
  journalctl --user -u "$(_unit_name "$name")"
}


# === Main ===
cmd="${1:-help}"
case "$cmd" in
  help|-h|--help) _print_help ;;
  config) shift; _cmd_config "$@" ;;
  mount) shift; _cmd_mount "$@" ;;
  enable) shift; _cmd_enable "$@" ;;
  disable) shift; _cmd_disable "$@" ;;
  uninstall) shift; _cmd_uninstall "$@" ;;
  status) shift; _cmd_status "$@" ;;
  log) shift; _cmd_log "$@" ;;
  logs) shift; _cmd_log "$@" ;;
  *) _die "Unknown command: $cmd. Try '$0 help'." ;;
esac
