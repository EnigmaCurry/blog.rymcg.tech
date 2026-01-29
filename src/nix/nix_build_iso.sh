#!/usr/bin/env bash
set -euo pipefail

# nix-build-iso.sh
#
# Wizard -> writes a flake workspace -> builds ISO -> copies to ~/Downloads.
#
KEEP=0
OUTDIR="${HOME}/Downloads"
SYSTEM="x86_64-linux"

WORKDIR=""     # if set, we write workspace here
DO_BUILD=1     # default build, but if --output is used,
               # default becomes 0 unless --build passed

usage() {
  cat <<'EOF'
Usage: nix-build-iso.sh [options]

Options:
  --keep              Keep temporary build directory (also kept on failure).
  --outdir DIR        Where to copy the resulting ISO (default: ~/Downloads).
  --system SYSTEM     Nix system (default: x86_64-linux), e.g. aarch64-linux.
  --output DIR        Write workspace to DIR and exit without building
                      (unless --build).
  --build             Build ISO even if --output is set.
  -h, --help          Show help.

Examples:
  ./nix-build-iso.sh
  ./nix-build-iso.sh --keep
  ./nix-build-iso.sh --output ./build-iso-workdir
  ./nix-build-iso.sh --output ./build-iso-workdir --build --outdir ~/Downloads

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    --outdir) OUTDIR="${2:?missing arg}"; shift 2 ;;
    --system) SYSTEM="${2:?missing arg}"; shift 2 ;;
    --output) WORKDIR="${2:?missing arg}"; shift 2; DO_BUILD=0 ;;
    --build) DO_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo >&2 "Unknown option: $1"; usage; exit 2 ;;
  esac
done

NIX=(nix --extra-experimental-features "nix-command flakes")

if ! command -v nix >/dev/null 2>&1; then
  echo >&2 "ERROR: 'nix' not found. Install Nix first."
  exit 1
fi

ask() {
  local prompt="$1"
  local def="${2-}"
  local ans=""
  if [[ -n "$def" ]]; then
    read -r -p "$prompt [$def]: " ans
    echo "${ans:-$def}"
  else
    read -r -p "$prompt: " ans
    echo "$ans"
  fi
}

yesno() {
  local prompt="$1"
  local def="${2:-y}" # y/n
  local ans
  while true; do
    ans="$(ask "$prompt (y/n)" "$def")"
    case "${ans,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

# Decide workspace directory
IS_TEMP=0
if [[ -n "$WORKDIR" ]]; then
  mkdir -p "$WORKDIR"
  TMPDIR="$(cd "$WORKDIR" && pwd)"
else
  TMPDIR="$(mktemp -d -t nixos-iso-XXXXXX)"
  IS_TEMP=1
fi

cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    if [[ $IS_TEMP -eq 1 ]]; then
      echo >&2 "Build failed (exit $rc). Temp dir kept at: $TMPDIR"
    else
      echo >&2 "Failed (exit $rc). Workspace is at: $TMPDIR"
    fi
    exit "$rc"
  fi

  if [[ $IS_TEMP -eq 1 ]]; then
    if [[ "$KEEP" -eq 1 ]]; then
      echo "Keeping temp dir: $TMPDIR"
    else
      rm -rf "$TMPDIR"
    fi
  fi
}
trap cleanup EXIT

mask_psk() {
  local s="${1-}"
  [[ -z "$s" ]] && { echo ""; return; }
  # show only length + last 2 chars
  local n="${#s}"
  if (( n <= 2 )); then
    printf '%*s' "$n" | tr ' ' '*'
  else
    printf '%*s' $((n-2)) | tr ' ' '*'
    printf '%s' "${s: -2}"
  fi
}

confirm_review() {
  local wifi_line=""
  local serial_line=""
  local webhook_line=""

  if [[ "$WIFI_ENABLE" -eq 1 ]]; then
    wifi_line=$(
      printf "enabled\n    SSID: %s\n    PSK:  %s\n    NM:   %s\n" \
        "$WIFI_SSID" "$(mask_psk "$WIFI_PSK")" "$NM_CONN_NAME"
    )
  else
    wifi_line="disabled"
  fi

  if [[ "$SERIAL_ENABLE" -eq 1 ]]; then
    serial_line="enabled (${SERIAL_DEV}@${SERIAL_BAUD})"
  else
    serial_line="disabled"
  fi

  if [[ "$WEBHOOK_ENABLE" -eq 1 ]]; then
    webhook_line="enabled ($WEBHOOK_URL)"
  else
    webhook_line="disabled"
  fi

  echo
  echo "================ Review ================="
  echo "Workspace:     $TMPDIR"
  echo "System:        $SYSTEM"
  echo "Hostname:      $HOSTNAME"
  echo "SSH user:      $AUTH_USER"
  echo "SSH keys:      ${#SSH_KEYS[@]} key(s)"
  for k in "${SSH_KEYS[@]}"; do
    # show a shortened preview
    echo "  - ${k:0:48}..."
  done
  echo "WiFi:          $wifi_line"
  echo "Serial:        $serial_line"
  echo "Webhook:       $webhook_line"
  echo "Build now:     $([[ "$DO_BUILD" -eq 1 ]] && echo yes || echo no)"
  if [[ "$DO_BUILD" -eq 1 ]]; then
    echo "ISO outdir:    $OUTDIR"
    echo "ISO name:      ${HOSTNAME}-$(id -un)-$(date +%Y%m%d).iso"
  fi
  echo "========================================="
  echo

  if ! yesno "Proceed?" "y"; then
    echo "Aborted."
    exit 0
  fi
}

mkdir -p "$OUTDIR"

echo "Workspace: $TMPDIR"
echo
echo "== ISO customization wizard =="

HOSTNAME="$(ask "Installer hostname" "nixos-installer")"

# Which user gets authorized_keys?
AUTH_USER="root"
if yesno "Put SSH keys on the 'nixos' user instead of 'root'?" "n"; then
  AUTH_USER="nixos"
fi

# SSH keys (allow multiple)
declare -a SSH_KEYS=()

echo "Paste one or more SSH public keys. End with an empty line:"
while true; do
    IFS= read -r line || true
    [[ -z "$line" ]] && break
    SSH_KEYS+=("$line")
done

if [[ "${#SSH_KEYS[@]}" -eq 0 ]]; then
  echo >&2 "ERROR: No SSH keys provided."
  exit 1
fi

# WiFi
WIFI_ENABLE=0
WIFI_SSID=""
WIFI_PSK=""
NM_CONN_NAME="bootstrap-wifi"
NM_FILE=""

echo
if yesno "Pre-seed WiFi credentials into the ISO?" "n"; then
  WIFI_ENABLE=1
  WIFI_SSID="$(ask "WiFi SSID" "")"
  WIFI_PSK="$(ask "WiFi PSK (password)" "")"
  NM_CONN_NAME="$(ask "NetworkManager connection name" "bootstrap-wifi")"

  if [[ -z "$WIFI_SSID" || -z "$WIFI_PSK" ]]; then
    echo >&2 "ERROR: WiFi enabled but SSID/PSK missing."
    exit 1
  fi

  NM_FILE="${NM_CONN_NAME}.nmconnection"
  cat > "${TMPDIR}/${NM_FILE}" <<EOF
[connection]
id=${NM_CONN_NAME}
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
  chmod 0600 "${TMPDIR}/${NM_FILE}"
fi

# Serial
SERIAL_ENABLE=0
SERIAL_DEV="ttyS0"
SERIAL_BAUD="115200"

echo
if yesno "Enable serial console (kernel + serial getty)?" "y"; then
  SERIAL_ENABLE=1
  SERIAL_DEV="$(ask "Serial device" "ttyS0")"
  SERIAL_BAUD="$(ask "Serial baud rate" "115200")"
fi

# Webhook
WEBHOOK_ENABLE=0
WEBHOOK_URL=""

echo
if yesno "Enable webhook notify after network-online?" "n"; then
  WEBHOOK_ENABLE=1
  WEBHOOK_URL="$(ask "Webhook URL (will receive JSON POST)" "")"
  if [[ -z "$WEBHOOK_URL" ]]; then
    echo >&2 "ERROR: webhook enabled but URL is empty."
    exit 1
  fi

  cat > "${TMPDIR}/webhook-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL="${WEBHOOK_URL:-}"
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "WEBHOOK_URL is empty; exiting."
  exit 0
fi

# Avoid relying on `hostname` being in PATH: read kernel hostname directly.
HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"

# Best-effort primary IPv4: ask the routing table what we'd use to reach the internet.
IPV4="$(
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '/src/ { for (i=1;i<=NF;i++) if ($i=="src") { print $(i+1); exit } }'
)"

# Fallback: first global IPv4 address we can find.
if [[ -z "$IPV4" ]]; then
  IPV4="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')"
fi
IPV4="${IPV4:-}"

payload="$(printf '{"hostname":"%s","ip":"%s"}\n' "$HOSTNAME" "$IPV4")"

echo "Posting to webhook: $WEBHOOK_URL"
echo "Payload: $payload"
curl -fsSL -X POST -H 'Content-Type: application/json' --data "$payload" "$WEBHOOK_URL"
EOF
  chmod 0755 "${TMPDIR}/webhook-notify.sh"
fi

# Build Nix list for SSH keys
nix_escape() {
  local s="$1"
  # Strip CR if keys were pasted with Windows line endings
  s="${s//$'\r'/}"
  # Escape for Nix double-quoted strings (also prevent ${...} interpolation by escaping $)
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  printf '%s' "$s"
}

SSH_KEYS_NIX="$(
  printf '[\n'
  for k in "${SSH_KEYS[@]}"; do
    printf '  "%s"\n' "$(nix_escape "$k")"
  done
  printf ']\n'
)"

# Conditional blocks for flake.nix
WIFI_BLOCK=""
if [[ "$WIFI_ENABLE" -eq 1 ]]; then
  WIFI_BLOCK=$(cat <<EOF

    # --- NetworkManager + pre-seeded WiFi ---
    networking.networkmanager.enable = true;

    environment.etc."NetworkManager/system-connections/${NM_CONN_NAME}.nmconnection" = {
      mode = "0600";
      source = ./${NM_FILE};
    };
EOF
)
else
  WIFI_BLOCK=$(cat <<'EOF'

    # --- NetworkManager (useful for ethernet too) ---
    networking.networkmanager.enable = true;
EOF
)
fi

SERIAL_BLOCK=""
if [[ "$SERIAL_ENABLE" -eq 1 ]]; then
  SERIAL_BLOCK=$(cat <<EOF

    # --- Serial console ---
    boot.kernelParams = [ "console=${SERIAL_DEV},${SERIAL_BAUD}" ];

    systemd.services."serial-getty@${SERIAL_DEV}" = {
      enable = true;
      wantedBy = [ "getty.target" ];
    };
EOF
)
fi

WEBHOOK_BLOCK=""
if [[ "$WEBHOOK_ENABLE" -eq 1 ]]; then
  WEBHOOK_BLOCK=$(cat <<EOF

    # --- Webhook fires once network is up ---
    environment.etc."webhook-notify.sh" = {
      mode = "0755";
      source = ./webhook-notify.sh;
    };

    systemd.services.webhook-notify = {
      description = "POST hostname + local IP to webhook once network is up";
      wantedBy = [ "multi-user.target" ];

      after = [ "network-online.target" "NetworkManager-wait-online.service" ];
      wants = [ "network-online.target" "NetworkManager-wait-online.service" ];

      path = with pkgs; [ bash curl iproute2 gawk coreutils ];

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "2min";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        Environment = [ "WEBHOOK_URL=$(nix_escape "$WEBHOOK_URL")" ];
      };

      script = ''
        exec /etc/webhook-notify.sh
      '';
    };
EOF
)
fi

# Write flake.nix
cat > "${TMPDIR}/flake.nix" <<EOF
{
  description = "Headless NixOS installer ISO (SSH + serial + WiFi + tools)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs, ... }:
    let
      system = "${SYSTEM}";
      lib = nixpkgs.lib;
    in {
      nixosConfigurations.installer = lib.nixosSystem {
        inherit system;
        modules = [
          "\${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

          ({ config, pkgs, lib, ... }:
            let
              sshPubKeys = ${SSH_KEYS_NIX};
            in
            {
              networking.hostName = "$(nix_escape "$HOSTNAME")";
              networking.useDHCP = lib.mkDefault true;

              services.openssh.enable = true;
              services.openssh.settings = {
                PasswordAuthentication = false;
                KbdInteractiveAuthentication = false;
                PermitRootLogin = "prohibit-password";
              };

              users.users.${AUTH_USER}.openssh.authorizedKeys.keys = sshPubKeys;

${SERIAL_BLOCK}
${WIFI_BLOCK}

              environment.systemPackages = with pkgs; [
                git curl wget openssh rsync
                parted gptfdisk e2fsprogs btrfs-progs xfsprogs dosfstools
                cryptsetup lvm2 mdadm
                tmux neovim nano htop
                pciutils usbutils
                iproute2 iputils dnsutils
              ];
${WEBHOOK_BLOCK}
            })
        ];
      };

      packages.\${system}.iso =
        self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
EOF

# Write build.sh convenience script
cat > "${TMPDIR}/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
nix --extra-experimental-features "nix-command flakes" build .#iso -L

# Print the ISO path for convenience
if [[ -d result/iso ]]; then
  iso="$(find result/iso -maxdepth 1 -type f -name '*.iso' | head -n 1 || true)"
  if [[ -n "$iso" ]]; then
    echo "Built ISO: $iso"
  fi
fi
EOF
chmod +x "${TMPDIR}/build.sh"

echo
echo "Workspace generated at: $TMPDIR"
echo "Convenience build script: $TMPDIR/build.sh"

if [[ "$DO_BUILD" -ne 1 ]]; then
  echo "Skipping build (config-only mode)."
  exit 0
fi

confirm_review

echo
echo "== Building ISO =="
pushd "$TMPDIR" >/dev/null
time ./build.sh

ISO_PATH=""
if [[ -d "$TMPDIR/result/iso" ]]; then
  ISO_PATH="$(find "$TMPDIR/result/iso" -maxdepth 1 -type f -name '*.iso' | head -n 1 || true)"
fi

if [[ -z "$ISO_PATH" ]]; then
  echo >&2 "ERROR: Could not find built ISO under $TMPDIR/result/iso"
  exit 1
fi

# Name includes username + date (and hostname to avoid overwrites)
USERNAME="$(id -un)"
DATE_YYYYMMDD="$(date +%Y%m%d)"
DEST_NAME="${HOSTNAME}-${USERNAME}-${DATE_YYYYMMDD}.iso"
DEST="${OUTDIR}/${DEST_NAME}"

cp -f "$ISO_PATH" "$DEST"
popd >/dev/null

echo
echo "✅ ISO copied to: $DEST"
