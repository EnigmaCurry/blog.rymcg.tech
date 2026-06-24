#!/usr/bin/env bash
set -euo pipefail

# traefik_local_auth_proxy.sh
#
# Localhost-only Traefik proxy that forwards to a remote upstream endpoint,
# injecting an Authorization header on the forwarded request.
#
# This is useful when your upstream requires an HTTP Authorization token but
# your local client (e.g. Home Assistant integration) cannot set headers.
#
# Traefik resolution:
#   1) If `traefik` is in PATH, use it.
#   2) Else, if `nix` is in PATH, run Traefik via `nix run`.
#   3) Else, error.
#
# Also supports installing/enabling a systemd *user* service:
#   --install-user-service installs unit + config under ~/.config and enables it
#   --uninstall-user-service removes them (and disables)
#
# SECURITY NOTE:
#   Your token is written into a config file on disk (permissions restricted).
#   Anyone who can read your user files could potentially recover it.
#
# Default listen: 127.0.0.1:11435
# Default auth scheme: Bearer
# Default TLS verify: ON (use --insecure-skip-verify for self-signed upstreams)

usage() {
  cat <<'EOF'
Usage:
  traefik_local_auth_proxy.sh [options] [--install-user-service|--uninstall-user-service]

Options:
  --upstream URL              Remote upstream base URL (e.g. https://host:port) (or env AUTH_PROXY_UPSTREAM)
  --token TOKEN               Token to inject (or env AUTH_PROXY_TOKEN)
  --auth-header NAME          Header name to inject (default: Authorization)
  --auth-prefix STR           Prefix before token (default: "Bearer")
  --listen ADDR:PORT          Local listen address (default: 127.0.0.1:11435)
  --log-level LEVEL           Traefik log level (default: INFO)
  --insecure-skip-verify      Skip TLS cert verification to upstream (self-signed). Default: OFF
  --nix-traefik-ref REF       Nix ref to run Traefik (default: nixpkgs#traefik)

Service actions (systemd --user):
  --install-user-service      Install + enable + start user service (name: traefik-local-auth-proxy)
  --uninstall-user-service    Disable + stop + remove user service files

Other:
  -h, --help                  Show help

Examples:
  # Run in foreground
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'abc123'

  # Install & enable as user service
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'abc123' \
    --install-user-service

  # Basic auth style header (example)
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'dXNlcjpwYXNz' \
    --auth-header Authorization \
    --auth-prefix 'Basic' \
    --install-user-service

Notes:
  - The local proxy does NOT require auth; it injects the auth header to the upstream.
  - Listens on 127.0.0.1 by default (not accessible remotely).
EOF
}

# Defaults
LISTEN_ADDR="127.0.0.1:11435"
LOG_LEVEL="INFO"
INSECURE_SKIP_VERIFY="false"
AUTH_HEADER="Authorization"
AUTH_PREFIX="Bearer"
NIX_TRAEFIK_REF="nixpkgs#traefik"

# Inputs (can come from env)
UPSTREAM="${AUTH_PROXY_UPSTREAM:-}"
TOKEN="${AUTH_PROXY_TOKEN:-}"

# Service actions
DO_INSTALL_USER_SERVICE="false"
DO_UNINSTALL_USER_SERVICE="false"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM="${2:-}"; shift 2;;
    --token) TOKEN="${2:-}"; shift 2;;
    --auth-header) AUTH_HEADER="${2:-}"; shift 2;;
    --auth-prefix) AUTH_PREFIX="${2:-}"; shift 2;;
    --listen) LISTEN_ADDR="${2:-}"; shift 2;;
    --log-level) LOG_LEVEL="${2:-}"; shift 2;;
    --insecure-skip-verify) INSECURE_SKIP_VERIFY="true"; shift 1;;
    --nix-traefik-ref) NIX_TRAEFIK_REF="${2:-}"; shift 2;;
    --install-user-service) DO_INSTALL_USER_SERVICE="true"; shift 1;;
    --uninstall-user-service) DO_UNINSTALL_USER_SERVICE="true"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

if [[ "$DO_INSTALL_USER_SERVICE" == "true" && "$DO_UNINSTALL_USER_SERVICE" == "true" ]]; then
  echo "ERROR: Choose only one of --install-user-service or --uninstall-user-service" >&2
  exit 2
fi

need_inputs="true"
if [[ "$DO_UNINSTALL_USER_SERVICE" == "true" ]]; then
  need_inputs="false"
fi

if [[ "$need_inputs" == "true" ]]; then
  if [[ -z "$UPSTREAM" ]]; then
    echo "ERROR: --upstream (or env AUTH_PROXY_UPSTREAM) is required" >&2
    usage
    exit 2
  fi
  if [[ -z "$TOKEN" ]]; then
    echo "ERROR: --token (or env AUTH_PROXY_TOKEN) is required" >&2
    usage
    exit 2
  fi
fi

# Decide how to run Traefik
TRAEFIK_MODE=""
if command -v traefik >/dev/null 2>&1; then
  TRAEFIK_MODE="path"
elif command -v nix >/dev/null 2>&1; then
  TRAEFIK_MODE="nix"
else
  echo "ERROR: traefik not found in PATH, and nix not found either." >&2
  echo "Install traefik, or install nix so the script can run Traefik via nix." >&2
  exit 127
fi

# Service install paths (systemd --user)
SERVICE_NAME="traefik-local-auth-proxy"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
USER_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${SERVICE_NAME}"
USER_CFG_FILE="${USER_CFG_DIR}/dynamic.yml"
USER_ENV_FILE="${USER_CFG_DIR}/env"
USER_UNIT_FILE="${USER_SYSTEMD_DIR}/${SERVICE_NAME}.service"

write_dynamic_config_file() {
  local cfg_path="$1"
  umask 077
  cat > "$cfg_path" <<EOF
http:
  routers:
    local_auth_proxy:
      rule: "PathPrefix(\`/\`)"
      entryPoints: ["local"]
      service: "upstream"
      middlewares: ["inject-auth"]

  middlewares:
    inject-auth:
      headers:
        customRequestHeaders:
          ${AUTH_HEADER}: "${AUTH_PREFIX} ${TOKEN}"
EOF

  if [[ "$INSECURE_SKIP_VERIFY" == "true" ]]; then
    cat >> "$cfg_path" <<'EOF'

  serversTransports:
    upstream-transport:
      insecureSkipVerify: true
EOF
  fi

  cat >> "$cfg_path" <<EOF

  services:
    upstream:
      loadBalancer:
        passHostHeader: false
EOF

  if [[ "$INSECURE_SKIP_VERIFY" == "true" ]]; then
    cat >> "$cfg_path" <<'EOF'
        serversTransport: "upstream-transport"
EOF
  fi

  cat >> "$cfg_path" <<EOF
        servers:
          - url: "${UPSTREAM}"
EOF
  chmod 600 "$cfg_path"
}

install_user_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: systemctl not found. Is systemd available?" >&2
    exit 127
  fi

  mkdir -p "$USER_SYSTEMD_DIR" "$USER_CFG_DIR"
  chmod 700 "$USER_CFG_DIR"

  # Write env file (still stores secret on disk; permissions restricted)
  umask 077
  cat > "$USER_ENV_FILE" <<EOF
AUTH_PROXY_UPSTREAM=${UPSTREAM}
AUTH_PROXY_TOKEN=${TOKEN}
AUTH_HEADER=${AUTH_HEADER}
AUTH_PREFIX=${AUTH_PREFIX}
INSECURE_SKIP_VERIFY=${INSECURE_SKIP_VERIFY}
LISTEN_ADDR=${LISTEN_ADDR}
LOG_LEVEL=${LOG_LEVEL}
NIX_TRAEFIK_REF=${NIX_TRAEFIK_REF}
EOF
  chmod 600 "$USER_ENV_FILE"

  # Write dynamic config (bakes in header value)
  write_dynamic_config_file "$USER_CFG_FILE"

  # ExecStart: pin absolute traefik path if present; else use nix run
  local execstart=""
  if command -v traefik >/dev/null 2>&1; then
    execstart="$(command -v traefik)"
  else
    execstart="$(command -v nix) run ${NIX_TRAEFIK_REF} --"
  fi

  umask 077
  cat > "$USER_UNIT_FILE" <<EOF
[Unit]
Description=Traefik localhost auth-injecting proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/${SERVICE_NAME}/env
ExecStart=${execstart} \\
  --log.level=\${LOG_LEVEL} \\
  --entrypoints.local.address=\${LISTEN_ADDR} \\
  --providers.file.filename=%h/.config/${SERVICE_NAME}/dynamic.yml \\
  --providers.file.watch=true
Restart=on-failure
RestartSec=1

# Basic hardening (user service)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictSUIDSGID=true

ReadWritePaths=%h/.config/${SERVICE_NAME}
ReadWritePaths=%h/.cache/nix
ReadWritePaths=%h/.local/state/nix

[Install]
WantedBy=default.target
EOF
  chmod 600 "$USER_UNIT_FILE"

  systemctl --user daemon-reload
  systemctl --user enable --now "${SERVICE_NAME}.service"

  echo "Installed and started user service: ${SERVICE_NAME}.service"
  echo "Local endpoint: http://${LISTEN_ADDR}"
  echo "Test: curl -s http://${LISTEN_ADDR}/"
  echo "Logs: journalctl --user -u ${SERVICE_NAME}.service"
}

uninstall_user_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: systemctl not found. Is systemd available?" >&2
    exit 127
  fi

  systemctl --user disable --now "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  rm -f "$USER_UNIT_FILE"
  rm -rf "$USER_CFG_DIR"
  systemctl --user daemon-reload

  echo "Uninstalled user service: ${SERVICE_NAME}.service"
}

if [[ "$DO_UNINSTALL_USER_SERVICE" == "true" ]]; then
  uninstall_user_service
  exit 0
fi

if [[ "$DO_INSTALL_USER_SERVICE" == "true" ]]; then
  install_user_service
  exit 0
fi

# Foreground run mode: write temp config and exec Traefik (or nix run traefik)
umask 077
CFG="$(mktemp -t traefik-local-auth-proxy.XXXXXX.yml)"
cleanup() { rm -f "$CFG"; }
trap cleanup EXIT INT TERM

write_dynamic_config_file "$CFG"

echo "Starting Traefik localhost auth proxy:"
echo "  Listen : http://${LISTEN_ADDR}"
echo "  Upstream: ${UPSTREAM}"
echo "  Inject : ${AUTH_HEADER}: ${AUTH_PREFIX} <redacted>"
echo "  TLS skip-verify: ${INSECURE_SKIP_VERIFY}"
echo "  Config: ${CFG}"
echo
echo "Test:"
echo "  curl -s http://${LISTEN_ADDR}/"
echo

if [[ "$TRAEFIK_MODE" == "path" ]]; then
  exec traefik \
    --log.level="$LOG_LEVEL" \
    --entrypoints.local.address="$LISTEN_ADDR" \
    --providers.file.filename="$CFG" \
    --providers.file.watch=true
else
  exec nix run "$NIX_TRAEFIK_REF" -- \
    --log.level="$LOG_LEVEL" \
    --entrypoints.local.address="$LISTEN_ADDR" \
    --providers.file.filename="$CFG" \
    --providers.file.watch=true
fi
