#!/bin/bash

######################################################
#                   WireGuard P2P                    #
#  https://blog.rymcg.tech/blog/linux/wireguard_p2p  #
######################################################

set -euo pipefail

###################################
# Configurable Environment Vars  #
###################################

WG_INTERFACE="wg0"
WG_PORT="51820"
WG_CONFIG_DIR="/etc/wireguard"

###################################
# Internal Globals                #
###################################

PRIVATE_KEY_FILE="$WG_CONFIG_DIR/privatekey"
PUBLIC_KEY_FILE="$WG_CONFIG_DIR/publickey"
CONFIG_FILE="$WG_CONFIG_DIR/${WG_INTERFACE}.conf"
SERVICE_NAME="wg-quick@${WG_INTERFACE}"
ADDRESS_FILE="$WG_CONFIG_DIR/address"

###################################
# Functions                       #
###################################

load_address() {
    if [[ ! -f "$ADDRESS_FILE" ]]; then
        echo "Error: Address file not found at $ADDRESS_FILE. Run install with an address." >&2
        exit 1
    fi
    WG_ADDRESS=$(<"$ADDRESS_FILE")
}

dependencies() {
    if command -v wg >/dev/null 2>&1; then
        echo "WireGuard already installed. Skipping dependency installation."
        return
    fi

    echo "Installing dependencies..."
    if [ -f /etc/debian_version ]; then
        apt update
        apt install -y wireguard-tools wireguard curl
    elif [ -f /etc/fedora-release ]; then
        dnf install -y wireguard-tools curl
    elif [ -f /etc/arch-release ]; then
        pacman -Sy --noconfirm wireguard-tools curl
    else
        echo "Cannot detect platform. Please manually install the wireguard and curl packages for your system." >&2
        exit 1
    fi
}

generate_keys() {
    echo "Generating WireGuard keys..."
    mkdir -p "$WG_CONFIG_DIR"
    chmod 700 "$WG_CONFIG_DIR"
    cd "$WG_CONFIG_DIR"

    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        umask 077
        wg genkey | tee privatekey | wg pubkey > publickey
        echo "Keys generated."
    else
        echo "Keys already exist."
    fi
}

create_base_config() {
    echo "Creating base WireGuard config file..."

    tee "$CONFIG_FILE" > /dev/null <<EOF
[Interface]
Address = $WG_ADDRESS
PrivateKey = $(<"$PRIVATE_KEY_FILE")
ListenPort = $WG_PORT
SaveConfig = true
EOF

    echo "Base config created at $CONFIG_FILE"
}

get_add_peer_command() {
        echo ""
    echo "------------------------------------------------------------"
    echo "To add THIS node as a peer on another WireGuard server using this script, run:"
    echo ""
    local public_key
    public_key=$(<"$PUBLIC_KEY_FILE")

    local public_ip
    public_ip=$(curl -s ifconfig.me)
    load_address

    echo "./wireguard_p2p.sh add-peer $(hostname) ${public_ip}:${WG_PORT} ${public_key}" "${WG_ADDRESS%%/*}"
    echo ""
    echo "(Replace '$(hostname)' with your desired label for this peer.)"
    echo "------------------------------------------------------------"
    echo ""
}

add_peer() {
    load_address

    local name="$2"
    local endpoint="$3"
    local public_key="$4"
    local peer_ip="$5"

    if [[ -z "$name" || -z "$endpoint" || -z "$public_key" || -z "$peer_ip" ]]; then
        echo "Error: name, endpoint, public_key, and peer_ip cannot be blank." >&2
        exit 1
    fi

    echo "Adding peer to WireGuard interface..."

    wg set "$WG_INTERFACE" peer "$public_key" \
        allowed-ips "$peer_ip" \
        endpoint "$endpoint" \
        persistent-keepalive 25

    echo "Peer added live. Restarting interface to save into config..."
    wg-quick down "$WG_INTERFACE" || true
    wg-quick up "$WG_INTERFACE"

    echo "Peer added and saved: $name ($endpoint)"
}

remove_peer() {
    local public_key="$2"

    if [[ -z "$public_key" ]]; then
        echo "Error: public_key cannot be blank." >&2
        exit 1
    fi

    echo "Removing peer from WireGuard interface..."

    wg set "$WG_INTERFACE" peer "$public_key" remove

    echo "Peer removed live. Restarting interface to save into config..."
    wg-quick down "$WG_INTERFACE" || true
    wg-quick up "$WG_INTERFACE"

    echo "Peer removed and config saved."
}

install() {
    dependencies
    generate_keys

    local given_address="${2:-}"

    if [[ -f "$ADDRESS_FILE" ]]; then
        local saved_address
        saved_address=$(<"$ADDRESS_FILE")

        if [[ -n "$given_address" ]]; then
            # Check that given address contains a "/" character
            if [[ "$given_address" != */* ]]; then
                echo "Error: Address must include a CIDR subnet (example: 10.10.0.1/24)" >&2
                exit 1
            fi

            if [[ "$given_address" != "$saved_address" ]]; then
                echo "Error: Address already exists at $ADDRESS_FILE and differs from the given one."
                echo "Saved:   $saved_address"
                echo "Given:   $given_address"
                echo ""
                echo "If you want to change the WireGuard address, you must uninstall first:"
                echo ""
                echo "    ./wireguard_p2p.sh uninstall"
                echo ""
                exit 1
            fi
            # Addresses match; continue normally
        fi

        WG_ADDRESS="$saved_address"
        echo "Loaded existing address: $WG_ADDRESS"
    else
        if [[ -z "$given_address" ]]; then
            echo "Error: No address specified and no existing address file." >&2
            echo "Usage: $0 install <your-address-in-cidr>"
            exit 1
        fi

        # Check that given address contains a "/" character
        if [[ "$given_address" != */* ]]; then
            echo "Error: Address must include a CIDR subnet (example: 10.10.0.1/24)" >&2
            exit 1
        fi

        WG_ADDRESS="$given_address"
        mkdir -p "$WG_CONFIG_DIR"
        echo "$WG_ADDRESS" | tee "$ADDRESS_FILE" > /dev/null
        echo "Saved address to $ADDRESS_FILE"
    fi

    echo "Ensuring WireGuard service is fully stopped before reinstalling..."
    wg-quick down "$WG_INTERFACE" || true
    systemctl stop "$SERVICE_NAME" || true

    create_base_config

    echo "Bringing up WireGuard interface..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    echo "WireGuard installed and service started."

    get_add_peer_command
}

uninstall() {
    echo "Stopping and disabling service..."
    systemctl stop "$SERVICE_NAME" || true
    systemctl disable "$SERVICE_NAME" || true
    wg-quick down ${WG_INTERFACE} 2>/dev/null || true

    echo "Removing config and keys..."
    rm -f "$CONFIG_FILE" "$PRIVATE_KEY_FILE" "$PUBLIC_KEY_FILE" "$ADDRESS_FILE"

    echo "WireGuard config and keys removed."
}

status() {
    systemctl status "$SERVICE_NAME"
    echo
    wg
}

start() {
    echo "Starting WireGuard service..."
    systemctl start "$SERVICE_NAME"
}

stop() {
    echo "Stopping WireGuard service..."
    systemctl stop "$SERVICE_NAME"
}

help() {
    cat <<EOF
Usage: $0 <command>

Commands:
  dependencies                       Install required packages.
  install <address-cidr>             Install and configure WireGuard. Required first time.
  uninstall                          Remove WireGuard configuration and keys.
  status                             Show the WireGuard service status.
  start                              Start the WireGuard service.
  stop                               Stop the WireGuard service.
  import-key PRIVATE_KEY             Import a private key instead of generating one.
  add-peer NAME ENDPOINT PUBLIC_KEY  Add peer live and auto-save into config.
  remove-peer PUBLIC_KEY             Remove peer live and auto-save into config.
  provision-peer NAME ENDPOINT ADDRESS    Provision keys and .conf for a new peer.
  help                               Show this help message.

Make sure required environment variables are set before running.
EOF
}

import_key() {
    local private_key="$2"
    if [[ -z "$private_key" ]]; then
        echo "Error: private_key cannot be blank." >&2
        exit 1
    fi

    echo "Importing provided private key..."
    mkdir -p "$WG_CONFIG_DIR"
    chmod 700 "$WG_CONFIG_DIR"
    echo "$private_key" | tee "$PRIVATE_KEY_FILE" > /dev/null
    echo "$private_key" | wg pubkey | tee "$PUBLIC_KEY_FILE" > /dev/null
    echo "Key imported."
}

provision_peer() {
    shift
    load_address
    if [[ $# -ne 3 ]]; then
      echo "Usage: $0 provision-peer <name> <endpoint> <address/CIDR>" >&2
      exit 1
    fi


    local name="$1"
    local endpoint="$2"     # e.g. alice.example.com:51820
    local peer_cidr="$3"    # e.g. 10.15.0.4/32

    if [[ "$endpoint" != *:* ]]; then
        echo "Error: endpoint must be in host:port form" >&2
        exit 1
    fi
    local peer_host="${endpoint%:*}"
    local peer_port="${endpoint##*:}"

    local public_ip=$(curl -s ifconfig.me)

    # Directory for the new peer’s artifacts
    local dir="$WG_CONFIG_DIR/provisioned-peers"
    mkdir -p "$dir"
    chmod 700 "$dir"

    # Generate a fresh keypair
    umask 077
    wg genkey | tee "$dir/${name}.priv" \
      | wg pubkey > "$dir/${name}.pub"

    local priv="$dir/${name}.priv"
    local pub="$(<"$dir/${name}.pub")"
    local conf="$dir/${name}.conf"

    # Build the turnkey .conf
    {
      echo "[Interface]"
      echo "PrivateKey = $(<"$priv")"
      echo "Address    = $peer_cidr"
      echo "ListenPort = $peer_port"
      echo
      echo "[Peer]"
      echo "PublicKey           = $(<"$PUBLIC_KEY_FILE")"
      echo "Endpoint            = $public_ip:$WG_PORT"
      echo "AllowedIPs          = $WG_ADDRESS"
      echo "PersistentKeepalive = 25"
    } > "$conf"
    chmod 600 "$conf"

    # Print the add-peer command for THIS node
    cat <<EOF

▶️  Provisioned peer bundle for '$name':
    • $conf

▶️  To stitch '$name' into this node’s mesh, run:

./wireguard_p2p.sh add-peer \\
    $name \\
    $endpoint \\
    $pub \\
    $peer_cidr

Now copy ${name}.conf to your client, import & activate, then run the above add-peer command here.
EOF
}


main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi

    if [[ $# -eq 0 ]]; then
        help
        exit 0
    fi

    case "$1" in
        dependencies) dependencies ;;
        install) install "$@" ;;
        uninstall) uninstall ;;
        status) status ;;
        start) start ;;
        stop) stop ;;
        import-key)
            if [[ $# -ne 2 ]]; then
                echo "Usage: $0 import-key <private_key>" >&2
                exit 1
            fi
            import_key "$@"
            ;;
        add-peer)
            if [[ $# -eq 1 ]]; then
                get_add_peer_command
                exit 0
            elif [[ $# -ne 5 ]]; then
                echo "Usage: $0 add-peer <name> <endpoint> <public_key> <peer_ip>" >&2
                exit 1
            fi
            add_peer "$@"
            ;;
        remove-peer)
            if [[ $# -ne 2 ]]; then
                echo "Usage: $0 remove-peer <public_key>" >&2
                exit 1
            fi
            remove_peer "$@"
            ;;
        provision-peer)
            provision_peer "$@"
            ;;
        help|-h|--help) help ;;
        *)
            echo "Unknown command: $1" >&2
            help
            exit 1
            ;;
    esac
}

###################################
# Entrypoint                      #
###################################

main "$@"
