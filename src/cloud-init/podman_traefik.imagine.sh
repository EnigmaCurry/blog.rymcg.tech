#!/bin/bash
parse_args() {
    # Parse named arguments from string, matching the provided explicit arg names
    # eg: parse_args "ACME_EMAIL=you@example.com OTHER=other" ACME_EMAIL OTHER
    # args: ARG_STRING ARG1 [ARG2 ...]
    # no positional arguments allowed.
    if [[ $# < 2 ]]; then
        echo "parse_args usage: ARG_STRING ARG1 [ARG2 ...]"
    fi
    ARG_STRING=$1
    shift
    declare -A ARG_NAMES
    for name in $@; do
        ARG_NAMES["$name"]=1
    done
    parse() {
        # Tokenize ARG_STRING to preserve spaces inside quotes
        eval 'for arg in '$@'; do echo $arg; done' |
            while IFS= read -r arg; do
                if [[ $arg =~ ^([a-zA-Z][a-zA-Z0-9_]*)=(.+)$ ]]; then
                    var=${BASH_REMATCH[1]}
                    val=${BASH_REMATCH[2]}
                    if [[ ${ARG_NAMES[$var]-X} != ${ARG_NAMES[$var]} ]]; then
                        echo "## Error: parse_args received unexpected argument: ${var}" >&2
                        exit 1
                    fi
                    #echo "## Parsed named argument: ${var}=\"${val}\"" >&2
                    echo "${var}=\"${val}\""
                else
                    #echo "## Error: parse_args received un-named argument: $arg" >&2
                    exit
                fi
            done
    }
    eval $(parse ${ARG_STRING})
}

traefik() {
    (
        parse_args "$@" SERVICE SERVICE_USER ACME_CA ACME_EMAIL
        SERVICE=${SERVICE:-traefik}
        SERVICE_USER=${SERVICE_USER:-podman-${SERVICE}}
        IMAGE=${IMAGE:traefik:latest}
        ACME_CA=${ACME_CA:-https://acme-v02.api.letsencrypt.org/directory}
        ACME_EMAIL=${ACME_EMAIL:-you@example.com}
        NETWORK_ARGS="--cap-add NET_BIND_SERVICE --network web -p 80:80 -p 443:443"
        VOLUME_ARGS="-v /etc/sysconfig/${SERVICE}.d:/etc/traefik/"

        container ${SERVICE} ${IMAGE} "${NETWORK_ARGS} ${VOLUME_ARGS}"
    )
}

container() {
    if [[ $# < 2 ]]; then
        echo "container() usage: "
        echo "  SERVICE_NAME IMAGE [\"PODMAN_ARGS\" [CMD_ARGS ...]]"
        exit 1
    fi
    ## Template function to create a systemd unit for a podman container
    ## Expects environment file at /etc/sysconfig/${SERVICE}
    local SERVICE=$1
    local IMAGE=$2
    local PODMAN_ARGS="${BASE_PODMAN_ARGS} $3"
    local CMD_ARGS=${@:4}
    local SERVICE_USER=${SERVICE_USER:-podman-${SERVICE}}
    # Create environment file
    for var in "${!SERVICE[@]}"; do
    done
    touch /etc/sysconfig/${SERVICE}

    # Create host user account to mirror container user:
    if ! id -u ${SERVICE_USER}; then
        useradd -m ${SERVICE_USER}
    fi
    local SERVICE_UID=$(id -u ${SERVICE_USER})
    local SERVICE_GID=$(id -g ${SERVICE_USER})
    chown root:${SERVICE_USER} /etc/sysconfig/${SERVICE}
    # Create systemd unit:
    cat <<EOF > /etc/systemd/system/${SERVICE}.service
[Unit]
After=network-online.target

[Service]
ExecStartPre=-/usr/bin/podman rm -f ${SERVICE}
ExecStart=/usr/bin/podman run --name ${SERVICE} --user ${SERVICE_UID}:${SERVICE_GID} --rm --env-file /etc/sysconfig/${SERVICE} ${PODMAN_ARGS} ${IMAGE} ${CMD_ARGS}
ExecStop=/usr/bin/podman stop ${SERVICE}
SyslogIdentifier=${SERVICE}
Restart=always

[Install]
WantedBy=network-online.target
EOF

    systemctl enable ${SERVICE}
    systemctl restart ${SERVICE}
}

proxy() {
    
}

secret() {
    ## memoize (write once) secrets saved in PODMAN_TRAEFIK_SECRETS_DIR
    ## args: SECRET_NAME [DEFAULT_VALUE_IF_NOT_ALREADY_SET]
    ## If SECRET_NAME already exists, return it immediately. Otherwise: if
    ## provided a single argument, generate a new password and save it with the
    ## given SECRET_NAME. If provided two arguments, set the provided default
    ## value. (Force creation of new secret with `--new` overwriting existing)
    ## Print the current memoized value.
    PARAMS=""
    while (( "$#" )); do
        case "$1" in
            --new)
                local FORCE_SET=true
                shift
                ;;
            -*|--*=) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                exit 1
                ;;
            *) # preserve positional arguments
                PARAMS="$PARAMS $1"
                shift
                ;;
        esac
    done
    # reset positional parameters
    eval set -- "$PARAMS"

    if [ -v FORCE_SET ] || [ ! -f ${PODMAN_TRAEFIK_SECRETS_DIR}/$1 ]; then
        # Create or set the password:
        umask og-rw
        if [ $# = 1 ]; then
            # Create password:
            head -c 16 /dev/urandom | base64 | cut -d "=" -f 1 > \
                ${PODMAN_TRAEFIK_SECRETS_DIR}/$1
        elif [ $# = 2 ]; then
            # Set provided secret:
            echo $2 > ${PODMAN_TRAEFIK_SECRETS_DIR}/$1
        else
            echo "Error: secret bad number of args: $@"
            exit 1
        fi
        # Echo the secret
        cat ${PODMAN_TRAEFIK_SECRETS_DIR}/$1
    fi
}

init() {
    ## Stuff we want to run when this script is sourced:
    ## this function self-destructs and is not exported.
    shopt -s extglob
    export PODMAN_TRAEFIK_SECRETS_DIR=/var/local/podman_traefik/secrets
    if [ $UID != 0 ]; then
        echo "Sorry ${USER}, you can only run this script as root."
        exit 1
    fi
    if [ ! -d ${PODMAN_TRAEFIK_SECRETS_DIR} ]; then
        mkdir -p ${PODMAN_TRAEFIK_SECRETS_DIR}
        chmod 0700 ${PODMAN_TRAEFIK_SECRETS_DIR}
    fi
    unset init
}

init
