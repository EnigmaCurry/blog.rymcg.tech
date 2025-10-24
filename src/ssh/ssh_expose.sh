#!/bin/bash

######################################################
#             SSH Reverse Tunnel Manager             #
#   https://blog.rymcg.tech/blog/linux/ssh_expose    #
######################################################

stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
fault(){ test -n "$1" && error "$1"; stderr "Exiting."; exit 1; }
print_array(){ printf '%s\n' "$@"; }
check_var() {
    local missing=()
    for varname in "$@"; do
        if [[ -z "${!varname}" ]]; then
            missing+=("$varname")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        __help
        echo ""
        echo "## Error: Missing:"
        for var in "${missing[@]}"; do
            echo "   - $var"
        done
        echo ""
        exit 1
    fi
}
check_num(){
    local var=$1
    check_var var
    if ! [[ ${!var} =~ ^[0-9]+$ ]]; then
        fault "${var} is not a number: '${!var}'"
    fi
}
debug_var(){ local var=$1; check_var var; stderr "## DEBUG: ${var}=${!var}"; }
check_deps(){
    missing=""
    for var in "$@"; do
        if ! command -v "$var" >/dev/null 2>&1; then
            missing="${missing} ${var}"
        fi
    done
    if [[ -n "$missing" ]]; then fault "Missing dependencies:${missing}"; fi
}

__print_active_tunnels() {
    tunnels=($(systemctl --user list-units --all --no-legend --no-pager --plain --state=active | awk '/^reverse-tunnel-.*(\.scope|\.service)/{print $1}'))
    if [ ${#tunnels[@]} -eq 0 ]; then
        echo "## No active tunnels."
    else
        parsed=()
        for tunnel in "${tunnels[@]}"; do
            name="${tunnel#reverse-tunnel-}"
            name="${name%.scope}"
            name="${name%.service}"
            host=$(cut -d'-' -f1 <<< "$name")
            public_port=$(cut -d'-' -f2 <<< "$name")
            private_port=$(cut -d'-' -f3 <<< "$name")
            type="ephemeral"
            [[ "$tunnel" == *.service ]] && type="persistent"
            parsed+=("$host $public_port $private_port $type")
        done

        printf "\n\e[1m%-15s %-12s %-12s %-12s\e[0m\n" "HOST" "PUBLIC_PORT" "LOCAL_PORT" "TYPE"
        printf "\e[1m%-15s %-12s %-12s %-12s\e[0m\n" "----" "-----------" "------------" "----"
        printf "%s\n" "${parsed[@]}" | sort -k1,1 -k2,2n | while read -r host public private type; do
            printf "%-15s %-12s %-12s %-12s\n" "$host" "$public" "$private" "$type"
        done
    fi
}

__create_persistent_tunnel() {
    local host=$1 public_port=$2 local_port=$3
    UNIT="reverse-tunnel-${host}-${public_port}-${local_port}"
    mkdir -p "${HOME}/.config/systemd/user"
    SERVICE_FILE="${HOME}/.config/systemd/user/${UNIT}.service"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Reverse SSH Tunnel for ${host} (Public: ${public_port}, Local: ${local_port})
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/autossh -o StrictHostKeyChecking=accept-new -o ControlMaster=no -o ControlPersist=no -o ControlPath=none -N -M 0 -R 0.0.0.0:${public_port}:0.0.0.0:${local_port} ${host}
Restart=always
RestartSec=10
StartLimitBurst=100
StartLimitIntervalSec=300

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${UNIT}.service"
    systemctl --user start "${UNIT}.service"
    systemctl --user status "${UNIT}.service" --no-pager
    echo
    echo "Persistent tunnel created and started."

    __print_active_tunnels

    if [ ! -f "/var/lib/systemd/linger/$USER" ]; then
        echo -e "\nWARNING: Systemd linger not enabled for $USER."
        echo "Run: sudo loginctl enable-linger ${USER}"
    fi
}

__one_shot_tunnel() {
    local host=$1 public_port=$2 local_port=$3
    check_var host public_port local_port
    UNIT="reverse-tunnel-${host}-${public_port}-${local_port}"
    systemd-run \
        --user \
        --unit="$UNIT" \
        --scope autossh \
        -o StrictHostKeyChecking=accept-new \
        -o ControlMaster=no \
        -o ControlPersist=no \
        -o ControlPath=none \
        -N -M 0 \
        -R 0.0.0.0:"${public_port}":0.0.0.0:"${local_port}" \
        "${host}" &
    echo "## Reverse tunnel started."
    #debug_var public_port
    #debug_var local_port
    sleep 2
    echo
}

__close_all_tunnels() {
    tunnels=($(systemctl --user list-units --all --no-legend --no-pager --plain --state=active | awk '/^reverse-tunnel-.*(\.scope|\.service)/{print $1}'))
    if [ ${#tunnels[@]} -eq 0 ]; then
        echo "## No active tunnels to close."
    else
        for tunnel in "${tunnels[@]}"; do
            systemctl --user stop "$tunnel"
            [[ "$tunnel" == *.service ]] && systemctl --user disable "$tunnel" && rm -f "${HOME}/.config/systemd/user/$tunnel"
        done
        systemctl --user daemon-reload
        echo "## All tunnels closed."
    fi
    __print_active_tunnels
}

__close_tunnel() {
    local host=$1 public_port=$2 local_port=$3
    UNIT="reverse-tunnel-${host}-${public_port}-${local_port}"
    if systemctl --user is-active --quiet "${UNIT}.scope"; then
        systemctl --user stop "${UNIT}.scope" && echo "Ephemeral tunnel closed."
    elif systemctl --user is-active --quiet "${UNIT}.service"; then
        systemctl --user stop "${UNIT}.service" && systemctl --user disable "${UNIT}.service"
        rm -f "${HOME}/.config/systemd/user/${UNIT}.service" && echo "Persistent tunnel closed."
    else
        echo "No tunnel found: ${UNIT}."
    fi
    __print_active_tunnels
}

__reconfigure_sshd() {
    if [[ $# -lt 2 ]]; then
        __help
        exit 1
    fi
    local HOST=$1
    shift
    ssh "$HOST" "sudo whoami" 2>/dev/null | grep -q '^root$' || fault "Cannot run sudo on remote host ${HOST}"

    TMP_FILE=$(ssh "$HOST" "mktemp /tmp/sshd_config.XXXXXX")
    [[ -z "$TMP_FILE" ]] && fault "Failed to create remote temp file."

    echo "Created temporary file ${TMP_FILE} on ${HOST}"

    ssh "$HOST" "sudo cp /etc/ssh/sshd_config $TMP_FILE"

    for CONFIG in "$@"; do
        KEY=$(cut -d= -f1 <<< "$CONFIG")
        VALUE=$(cut -d= -f2 <<< "$CONFIG")
        ssh "$HOST" "sudo sed -i '/^#${KEY}/d; /^${KEY}/d' $TMP_FILE && echo '${KEY} ${VALUE}' | sudo tee -a $TMP_FILE"
    done

    if ssh "$HOST" "sudo sshd -t -f $TMP_FILE"; then
        echo "Configuration valid, applying..."
        ssh "$HOST" "sudo mv $TMP_FILE /etc/ssh/sshd_config && sudo systemctl restart sshd"
    else
        echo "Invalid config, cancelling."
        ssh "$HOST" "sudo rm -f $TMP_FILE"
    fi
}

__subcommand_port() {
    local persistent="" close="" host="" public_port="" local_port=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --persistent) persistent="yes"; shift ;;
            --close) close="yes"; shift ;;
            --close-all) __close_all_tunnels; exit 0 ;;
            -*)
                fault "Unknown option: $1"
                ;;
            *)
                if [[ -z "$host" ]]; then host="$1"
                elif [[ -z "$public_port" ]]; then public_port="$1"
                elif [[ -z "$local_port" ]]; then local_port="$1"
                else fault "Too many positional arguments."
                fi
                shift
                ;;
        esac
    done

    check_var host public_port local_port
    check_num public_port
    check_num local_port
    check_deps autossh

    if [[ "$close" == "yes" ]]; then
        __close_tunnel "$host" "$public_port" "$local_port"
    else
        if [[ "$persistent" == "yes" ]]; then
            __create_persistent_tunnel "$host" "$public_port" "$local_port"
        else
            __one_shot_tunnel "$host" "$public_port" "$local_port"
            __print_active_tunnels
        fi
    fi
}

__subcommand_sshd_config() {
    __reconfigure_sshd "$@"
}

main() {
    if [[ $# -lt 1 ]]; then
        __help
        exit 1
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        port) __subcommand_port "$@" ;;
        sshd-config) __subcommand_sshd_config "$@" ;;
        list) __print_active_tunnels ;;
        *) error "Unknown subcommand: $subcommand"; __help; exit 1 ;;
    esac
}

__help() {
    SCRIPT=$(basename $0)
    echo "## Usage: $SCRIPT <subcommand> [options]"
    echo ""
    echo "Subcommands:"
    echo "  port           Expose a local port to a remote SSH server"
    echo "  sshd-config    Reconfigure a remote sshd server config"
    echo "  list           List active tunnels"
    echo ""
    echo "Port usage:"
    echo "  $SCRIPT port [--persistent|--close] HOST PUBLIC_PORT LOCAL_PORT"
    echo "  $SCRIPT port HOST PUBLIC_PORT LOCAL_PORT [--persistent|--close]"
    echo "  $SCRIPT port --close-all"
    echo ""
    echo "Examples (HOST=sentry):"
    echo "  $SCRIPT sshd-config sentry GatewayPorts=yes AllowTcpForwarding=yes"
    echo ""
    echo "  $SCRIPT port sentry 8888 8000"
    echo "  $SCRIPT port --persistent sentry 8888 8000"
    echo "  $SCRIPT port sentry 8888 8000 --close"
    echo "  $SCRIPT port --close-all"
    echo ""
    echo "  $SCRIPT list"
    echo ""
    __print_active_tunnels
}

main "$@"
