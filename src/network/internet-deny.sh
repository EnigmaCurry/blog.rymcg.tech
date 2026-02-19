#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# LAN-only "internet kill switch" using iptables/ip6tables
#
# - Keeps LAN (RFC1918 IPv4) working
# - Allows DNS to anywhere (UDP/TCP 53)
# - Allows additional exception destinations (hostname/IP)
# - Blocks everything else outbound
#
# Works on: iptables-legacy and iptables-nft (compat).
# ============================================================

# ----- User config -----
EXCEPTIONS=(
  # "example.com"
  # "1.1.1.1"
  # "2606:4700:4700::1111"
)

# Leave these empty to allow ALL ports/protocols to exception IPs.
# If you set them, only those ports will be allowed to exception IPs (DNS always allowed).
EXCEPTION_TCP_PORTS=(
  # 443 22
)
EXCEPTION_UDP_PORTS=(
  # 123
)
# ----------------------

CHAIN_V4="LANONLY_OUT"
CHAIN_V6="LANONLY6_OUT"

# RFC1918 + loopback
LAN_V4_CIDRS=( "127.0.0.0/8" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" )
# IPv6 LAN-ish: loopback, link-local, ULA (if you use it)
LAN_V6_CIDRS=( "::1/128" "fe80::/10" "fc00::/7" )

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: lanonly.sh {on|off|status}

on      Enable LAN-only mode
off     Disable LAN-only mode
status  Show whether LAN-only mode is active
EOF
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if have sudo; then
      exec sudo -E "$0" "$@"
    fi
    echo "ERROR: must run as root (sudo not found)." >&2
    exit 1
  fi
}

# ---- resolution helpers ----

is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_ipv6() { [[ "$1" == *:* ]]; }

resolve_one() {
  # prints resolved IPs (v4/v6) one per line
  local name="$1"

  # literal IP
  if is_ipv4 "$name" || is_ipv6 "$name"; then
    printf '%s\n' "$name"
    return 0
  fi

  # getent (preferred)
  if have getent; then
    getent ahosts "$name" 2>/dev/null | awk '{print $1}' | sort -u
    return 0
  fi

  # dig fallback
  if have dig; then
    { dig +short A "$name"; dig +short AAAA "$name"; } 2>/dev/null | awk 'NF' | sort -u
    return 0
  fi

  # host fallback
  if have host; then
    host -t A "$name" 2>/dev/null | awk '/has address/ {print $4}'
    host -t AAAA "$name" 2>/dev/null | awk '/has IPv6 address/ {print $5}'
    return 0
  fi

  echo "WARNING: no resolver tool (getent/dig/host) to resolve: $name" >&2
  return 0
}

resolve_exceptions() {
  EXC_V4=()
  EXC_V6=()

  local item ip
  local -A seen4=()
  local -A seen6=()

  for item in "${EXCEPTIONS[@]:-}"; do
    [[ -z "$item" ]] && continue
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      if is_ipv4 "$ip"; then
        [[ -n "${seen4[$ip]:-}" ]] && continue
        seen4["$ip"]=1
        EXC_V4+=("$ip")
      elif is_ipv6 "$ip"; then
        [[ -n "${seen6[$ip]:-}" ]] && continue
        seen6["$ip"]=1
        EXC_V6+=("$ip")
      fi
    done < <(resolve_one "$item" || true)
  done
}

# ---- iptables chain management ----

v4_active() {
  iptables -C OUTPUT -j "$CHAIN_V4" >/dev/null 2>&1
}

v6_active() {
  ip6tables -C OUTPUT -j "$CHAIN_V6" >/dev/null 2>&1
}

ensure_chain_v4() {
  iptables -N "$CHAIN_V4" 2>/dev/null || true
  iptables -F "$CHAIN_V4"
  # ensure jump from OUTPUT (at top)
  iptables -C OUTPUT -j "$CHAIN_V4" 2>/dev/null || iptables -I OUTPUT 1 -j "$CHAIN_V4"
}

ensure_chain_v6() {
  ip6tables -N "$CHAIN_V6" 2>/dev/null || true
  ip6tables -F "$CHAIN_V6"
  ip6tables -C OUTPUT -j "$CHAIN_V6" 2>/dev/null || ip6tables -I OUTPUT 1 -j "$CHAIN_V6"
}

remove_chain_v4() {
  iptables -D OUTPUT -j "$CHAIN_V4" 2>/dev/null || true
  iptables -F "$CHAIN_V4" 2>/dev/null || true
  iptables -X "$CHAIN_V4" 2>/dev/null || true
}

remove_chain_v6() {
  ip6tables -D OUTPUT -j "$CHAIN_V6" 2>/dev/null || true
  ip6tables -F "$CHAIN_V6" 2>/dev/null || true
  ip6tables -X "$CHAIN_V6" 2>/dev/null || true
}

# ---- rule population ----

populate_v4_rules() {
  # Always allow DNS anywhere
  iptables -A "$CHAIN_V4" -p udp --dport 53 -j ACCEPT
  iptables -A "$CHAIN_V4" -p tcp --dport 53 -j ACCEPT

  # Allow LAN ranges
  local cidr
  for cidr in "${LAN_V4_CIDRS[@]}"; do
    iptables -A "$CHAIN_V4" -d "$cidr" -j ACCEPT
  done

  # Allow exceptions (resolved at enable time)
  local ip p
  for ip in "${EXC_V4[@]:-}"; do
    [[ -z "$ip" ]] && continue
    if [[ "${#EXCEPTION_TCP_PORTS[@]}" -eq 0 && "${#EXCEPTION_UDP_PORTS[@]}" -eq 0 ]]; then
      iptables -A "$CHAIN_V4" -d "$ip" -j ACCEPT
    else
      for p in "${EXCEPTION_TCP_PORTS[@]:-}"; do
        [[ -z "$p" ]] && continue
        iptables -A "$CHAIN_V4" -p tcp -d "$ip" --dport "$p" -j ACCEPT
      done
      for p in "${EXCEPTION_UDP_PORTS[@]:-}"; do
        [[ -z "$p" ]] && continue
        iptables -A "$CHAIN_V4" -p udp -d "$ip" --dport "$p" -j ACCEPT
      done
    fi
  done

  # Drop everything else
  iptables -A "$CHAIN_V4" -j DROP
}

populate_v6_rules() {
  # Always allow DNS anywhere
  ip6tables -A "$CHAIN_V6" -p udp --dport 53 -j ACCEPT
  ip6tables -A "$CHAIN_V6" -p tcp --dport 53 -j ACCEPT

  # Allow LAN-ish IPv6
  local cidr
  for cidr in "${LAN_V6_CIDRS[@]}"; do
    ip6tables -A "$CHAIN_V6" -d "$cidr" -j ACCEPT
  done

  # Allow exceptions
  local ip p
  for ip in "${EXC_V6[@]:-}"; do
    [[ -z "$ip" ]] && continue
    if [[ "${#EXCEPTION_TCP_PORTS[@]}" -eq 0 && "${#EXCEPTION_UDP_PORTS[@]}" -eq 0 ]]; then
      ip6tables -A "$CHAIN_V6" -d "$ip" -j ACCEPT
    else
      for p in "${EXCEPTION_TCP_PORTS[@]:-}"; do
        [[ -z "$p" ]] && continue
        ip6tables -A "$CHAIN_V6" -p tcp -d "$ip" --dport "$p" -j ACCEPT
      done
      for p in "${EXCEPTION_UDP_PORTS[@]:-}"; do
        [[ -z "$p" ]] && continue
        ip6tables -A "$CHAIN_V6" -p udp -d "$ip" --dport "$p" -j ACCEPT
      done
    fi
  done

  # Drop everything else
  ip6tables -A "$CHAIN_V6" -j DROP
}

do_on() {
  need_root "$@"
  have iptables || { echo "ERROR: iptables not found." >&2; exit 1; }

  resolve_exceptions

  ensure_chain_v4
  populate_v4_rules

  if have ip6tables; then
    ensure_chain_v6
    populate_v6_rules
  fi

  echo "LAN-only enabled."
  if [[ "${#EXC_V4[@]}" -gt 0 || "${#EXC_V6[@]}" -gt 0 ]]; then
    echo "Resolved exceptions:"
    [[ "${#EXC_V4[@]}" -gt 0 ]] && printf '  IPv4: %s\n' "${EXC_V4[@]}"
    [[ "${#EXC_V6[@]}" -gt 0 ]] && printf '  IPv6: %s\n' "${EXC_V6[@]}"
  fi
}

do_off() {
  need_root "$@"
  have iptables || { echo "ERROR: iptables not found." >&2; exit 1; }

  remove_chain_v4
  if have ip6tables; then
    remove_chain_v6
  fi
  echo "LAN-only disabled."
}

do_status() {
  need_root "$@"
  have iptables || { echo "iptables not found." >&2; exit 1; }

  if v4_active; then
    echo "IPv4 LAN-only: ON"
  else
    echo "IPv4 LAN-only: OFF"
  fi

  if have ip6tables; then
    if v6_active; then
      echo "IPv6 LAN-only: ON"
    else
      echo "IPv6 LAN-only: OFF"
    fi
  else
    echo "IPv6 LAN-only: OFF (ip6tables missing)"
  fi
}

main() {
  [[ $# -eq 1 ]] || { usage; exit 1; }
  case "$1" in
    on) do_on "$@" ;;
    off) do_off "$@" ;;
    status) do_status "$@" ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
