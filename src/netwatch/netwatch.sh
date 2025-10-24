#!/usr/bin/env bash
set -euo pipefail

### CONFIGURATION ###

# Interface to monitor (e.g. wg0, eth0)
NET_INTERFACE="enp1s0f0"

# Ping target
PING_HOST="198.60.22.2"
PING_COUNT=1

# RRD database location
RRD_FILE="/var/lib/netwatch/${NET_INTERFACE}.rrd"

# Systemd unit base name
UNIT_NAME="netwatch-${NET_INTERFACE}"

# Output PNG path for graph
GRAPH_FILES="/tmp/netwatch"

# Timer interval
TIMER_INTERVAL="1min"

### END CONFIGURATION ###

function log() {
  logger -t ${UNIT_NAME} "$*"}
}

function check_deps() {
  local deps=("$@")
  if [[ ${#deps[@]} -eq 0 ]]; then
    deps=(rrdtool ping ip logger)  # default dependencies
  fi

  local missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing+=("$dep")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing dependencies: ${missing[*]}"
    return 1
  fi
}

function create_rrd() {
  mkdir -p "$(dirname "$RRD_FILE")"
  if [[ ! -f "$RRD_FILE" ]]; then
    log "Creating RRD database at $RRD_FILE"
    rrdtool create "$RRD_FILE" \
      --step 60 \
      DS:status:GAUGE:120:0:1 \
      DS:rx:COUNTER:120:0:U \
      DS:tx:COUNTER:120:0:U \
      DS:ping:GAUGE:120:0:10000 \
      RRA:AVERAGE:0.5:1:1440 \
      RRA:AVERAGE:0.5:5:2016 \
      RRA:AVERAGE:0.5:60:8760
  fi
}

function run_check() {
  check_deps || exit 1
  create_rrd

  status=0
  rx=0
  tx=0
  ping_time=0

  if ip link show "$NET_INTERFACE" up &>/dev/null; then
    status=1
  fi

  rx=$(cat "/sys/class/net/${NET_INTERFACE}/statistics/rx_bytes" 2>/dev/null || echo 0)
  tx=$(cat "/sys/class/net/${NET_INTERFACE}/statistics/tx_bytes" 2>/dev/null || echo 0)

  PING_FILE=/tmp/netwatch_${NET_INTERFACE}_ping
  if ping -c "$PING_COUNT" -w 2 "$PING_HOST" > ${PING_FILE} 2>&1; then
    ping_time=$(grep 'time=' ${PING_FILE} | sed -E 's/.*time=([0-9.]+).*/\1/' | awk '{print int($1 + 0.5)}')
  fi

  log "Status=$status RX=$rx TX=$tx Ping=${ping_time}ms"
  rrdtool update "$RRD_FILE" N:$status:$rx:$tx:$ping_time
}

function install_timer() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: install must be run as root." >&2
    exit 1
  fi

  check_deps || exit 1
  create_rrd

  local systemd_dir="/etc/systemd/system"
  local abs_path
  abs_path=$(realpath "$0")

  cat > "${systemd_dir}/${UNIT_NAME}.service" <<EOF
[Unit]
Description=Network Monitor for $NET_INTERFACE

[Service]
Type=oneshot
ExecStart=${abs_path} run
EOF

  cat > "${systemd_dir}/${UNIT_NAME}.timer" <<EOF
[Unit]
Description=Run network monitor every $TIMER_INTERVAL

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now "${UNIT_NAME}.timer"
  log "Installed systemd timer for $NET_INTERFACE"
}

function uninstall_timer() {
  systemctl disable --now "${UNIT_NAME}.timer" || true
  rm -f "/etc/systemd/system/${UNIT_NAME}.service"
  rm -f "/etc/systemd/system/${UNIT_NAME}.timer"
  systemctl daemon-reload
  log "Uninstalled systemd timer for $NET_INTERFACE"
}

function check_status() {
  systemctl list-units --type=service --type=timer | grep -E "${UNIT_NAME}\.(service|timer)" || {
    echo "No active units found for ${UNIT_NAME}."
    exit 1
  }

  echo "Service status:"
  systemctl status "${UNIT_NAME}.service" || true
  echo
  echo "Timer status:"
  systemctl status "${UNIT_NAME}.timer" || true
}

function generate_graph() {
  check_deps || exit 1
  span="${1:-day}"
  case "$span" in
    day)   range=86400;  label="24h" ;;
    week)  range=$((7*86400));  label="7d" ;;
    month) range=$((30*86400)); label="30d" ;;
    year)  range=$((365*86400)); label="1y" ;;
    *)
      echo "Invalid span: $span"
      echo "Valid options: day, week, month, year"
      return 1
      ;;
  esac

  end_time=$(date +%s)
  start_time=$((end_time - range))

  if [[ ! -f "$RRD_FILE" ]]; then
      echo "RRD database missing: ${RRD_FILE}"
      exit 1
  fi

  mkdir -p "${GRAPH_FILES}"
  GRAPH_FILE="${GRAPH_FILES}/${UNIT_NAME}_${span}_stats.png"

  timestamp=$(date +"%F_%H%M%S_%Z")

  rrdtool graph "$GRAPH_FILE" \
          --start "$start_time" --end "$end_time" \
          --title "Network stats for $NET_INTERFACE ($label)" \
          --width 800 --height 300 \
          --vertical-label "bytes / ms / state" \
          DEF:rx="$RRD_FILE":rx:AVERAGE \
          DEF:tx="$RRD_FILE":tx:AVERAGE \
          DEF:ping="$RRD_FILE":ping:AVERAGE \
          DEF:status="$RRD_FILE":status:AVERAGE \
          LINE1:rx#00FF00:"RX Bytes" \
          LINE1:tx#0000FF:"TX Bytes" \
          LINE1:ping#FF00FF:"Ping (ms)" \
          LINE1:status#FF0000:"Status (1=up)" \
          COMMENT:"\\n" \
          "COMMENT:Last updated $timestamp"

  echo "Graph generated: $GRAPH_FILE"
}

function show_logs() {
    journalctl SYSLOG_IDENTIFIER=${UNIT_NAME} --no-pager --output short-iso
}

function serve() {
    check_deps python3
    cd "${GRAPH_FILES}"
    echo "## Serving $(echo "$(pwd | sed 's:/*$::')/")"

    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
import argparse
from http.server import HTTPServer, SimpleHTTPRequestHandler
import ipaddress
import sys

class IPRestrictedHandler(SimpleHTTPRequestHandler):
    allowed_networks = []

    def _client_allowed(self):
        client_ip = self.client_address[0]
        try:
            ip_obj = ipaddress.ip_address(client_ip)
            return any(ip_obj in net for net in self.allowed_networks)
        except ValueError:
            return False

    def do_GET(self):
        if not self._client_allowed():
            self.send_response(401)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"401 Unauthorized\n")
            return

        super().do_GET()

def main():
    parser = argparse.ArgumentParser(
        description="Simple HTTP server with IP allowlist."
    )
    parser.add_argument("--port", type=int, default=8000, help="Port to listen on")
    parser.add_argument(
        "--allow",
        action="append",
        metavar="IP/CIDR",
        help="Allowed IP address or CIDR block (can be specified multiple times)",
    )
    args = parser.parse_args()

    # Default to allow all IPv4 if none specified
    allowlist = args.allow or ["0.0.0.0/0"]

    try:
        IPRestrictedHandler.allowed_networks = [
            ipaddress.ip_network(a) for a in allowlist
        ]
    except ValueError as e:
        print(f"Invalid IP/CIDR in --allow: {e}", file=sys.stderr)
        sys.exit(1)

    server_address = ("", args.port)
    httpd = HTTPServer(server_address, IPRestrictedHandler)
    print(f"Serving on port {args.port}. Allowed: {', '.join(allowlist)}")
    httpd.serve_forever()

if __name__ == "__main__":
    main()
EOF
    python3 "$tmpfile" "$@"
    rm "$tmpfile"
}

function usage() {
  cat <<EOF
netwatch: Monitor network interface status, traffic, and ping latency using rrdtool.

Usage:
  $0 <subcommand>

Subcommands:
  run         Perform a single check of the network interface:
              - Verifies interface is up
              - Records RX/TX byte counters
              - Measures ping latency to configured host
              - Logs data to RRD file

  install     Install a systemd service and timer to run 'run' periodically
              (default: every ${TIMER_INTERVAL}).
              Creates:
                - /etc/systemd/system/${UNIT_NAME}.service
                - /etc/systemd/system/${UNIT_NAME}.timer

  uninstall   Remove the systemd service and timer created by 'install'.

  status      Show systemd status of the netwatch service and timer for this interface.

  log         Show logs from the journal for this netwatch service.

  deps        Check for required dependencies (rrdtool, ping, ip, logger).

  graph       Generate a 24-hour PNG graph of the monitored data:
              - RX/TX bytes
              - Ping latency
              - Interface up/down status
              Output files: ${GRAPH_FILES}

  serve [port]  Start HTTP server for the graph directory.

Configuration is defined at the top of this script:
  - NET_INTERFACE: Network interface to monitor (e.g., eth0, wg0)
  - PING_HOST:     IP address to ping
  - RRD_FILE:      Where RRD data is stored
  - GRAPH_FILE:    Output file for generated graph

Example:
  sudo $0 install
  sudo systemctl status ${UNIT_NAME}.timer
  $0 graph

EOF
  exit 1
}

case "${1:-}" in
  run) run_check && generate_graph day && generate_graph week && generate_graph year ;;
  install) install_timer ;;
  uninstall) uninstall_timer ;;
  deps) check_deps ;;
  graph) shift; generate_graph $@;;
  status) check_status ;;
  log) show_logs ;;
  logs) show_logs ;;
  serve) shift; serve $@;;
  *) usage ;;
esac
