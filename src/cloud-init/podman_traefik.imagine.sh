#!/bin/bash

parse_args() {
    # Parse named arguments from string, matching the provided explicit arg names
    # eg: parse_args "ACME_EMAIL=you@example.com OTHER=other" ACME_EMAIL OTHER
    # args: ARG_STRING ARG1 [ARG2 ...]
    # If positional arguments found, they are set the array $ARGS
    set +u
    if [[ $# < 1 ]]; then
        echo "## Error: not enough arguments for parse_args"
        echo "## parse_args usage: ARG_STRING ARG1 [ARG2 ...]"
        exit 1
    fi
    ARG_STRING=$1
    shift
    declare -A ARG_NAMES
    for name in $@; do
        ARG_NAMES["$name"]=1
    done
    ARGS=()
    parse() {
        # Tokenize ARG_STRING to preserve spaces inside quotes
        while IFS= read -r arg; do
            if [[ $arg =~ ^([a-zA-Z][a-zA-Z0-9_]*)=(.+)$ ]]; then
                var=${BASH_REMATCH[1]}
                val=${BASH_REMATCH[2]}
                if [[ ${ARG_NAMES[$var]-X} != ${ARG_NAMES[$var]} ]]; then
                    exit 1
                fi
                eval "${var}=\"${val}\""
            else
                echo $arg
                ARGS+=("$arg")
            fi
        done <<< $(eval 'for arg in '$@'; do echo $arg; done')
    }
    parse "${ARG_STRING}"
    set -u
}

traefik() {
    (
        ## Creates Traefik deployment
        ## example: traefik ACME_EMAIL=you@example.com IMAGE=traefik:v2.3
        ## parse_args parses arguments, and documents what those arguments are:
        eval parse_args "\"$@\"" SERVICE SERVICE_USER IMAGE ACME_CA ACME_EMAIL
        echo  "$ACME_CA"; exit
        ## Set defaults for any config left unspecified:
        SERVICE=${SERVICE:-traefik}
        SERVICE_USER=${SERVICE_USER:-podman-${SERVICE}}
        IMAGE=${IMAGE:-traefik:latest}
        ACME_CA=${ACME_CA:-https://acme-v02.api.letsencrypt.org/directory}
        ACME_EMAIL=${ACME_EMAIL:-you@example.com}


        ## Create the traefik service and container:
        #container ${SERVICE} ${IMAGE} PODMAN_ARGS="--cap-add NET_BIND_SERVICE --network web -p 80:80 -p 443:443 -v /etc/sysconfig/${SERVICE}.d:/etc/traefik/"
    )
}

container() {
    (
        echo "\"$@\""; exit
        eval parse_args "\"$@\"" SERVICE_USER PODMAN_ARGS
        echo ${PODMAN_ARGS[@]}
        if [[ ${#ARGS[@]} < 2 ]]; then
            echo "container() usage: "
            echo "  container SERVICE IMAGE [\"PODMAN_ARGS\" [CMD_ARGS ...]]"
            exit 1
        fi
        # Positional arguments:
        SERVICE=${ARGS[@]:0:1}
        IMAGE=${ARGS[@]:1:1}
        PODMAN_ARGS=${PODMAN_ARGS:-$ARGS[@]:2:1}
        CMD_ARGS=${ARGS[@]:3}


    )

#     if [[ $# < 2 ]]; then
#         echo "container() usage: "
#         echo "  SERVICE_NAME IMAGE [\"PODMAN_ARGS\" [CMD_ARGS ...]]"
#         exit 1
#     fi
#     ## Template function to create a systemd unit for a podman container
#     ## Expects environment file at /etc/sysconfig/${SERVICE}
#     local SERVICE=$1
#     local IMAGE=$2
#     local PODMAN_ARGS="${BASE_PODMAN_ARGS} $3"
#     local CMD_ARGS=${@:4}
#     local SERVICE_USER=${SERVICE_USER:-podman-${SERVICE}}
#     # Create environment file
#     for var in "${!SERVICE[@]}"; do
#         echo "TODO"
#     done
#     touch /etc/sysconfig/${SERVICE}

#     # Create host user account to mirror container user:
#     if ! id -u ${SERVICE_USER}; then
#         useradd -m ${SERVICE_USER}
#     fi
#     local SERVICE_UID=$(id -u ${SERVICE_USER})
#     local SERVICE_GID=$(id -g ${SERVICE_USER})
#     chown root:${SERVICE_USER} /etc/sysconfig/${SERVICE}
#     # Create systemd unit:
#     cat <<EOF > /etc/systemd/system/${SERVICE}.service
# [Unit]
# After=network-online.target

# [Service]
# ExecStartPre=-/usr/bin/podman rm -f ${SERVICE}
# ExecStart=/usr/bin/podman run --name ${SERVICE} --user ${SERVICE_UID}:${SERVICE_GID} --rm --env-file /etc/sysconfig/${SERVICE} ${PODMAN_ARGS} ${IMAGE} ${CMD_ARGS}
# ExecStop=/usr/bin/podman stop ${SERVICE}
# SyslogIdentifier=${SERVICE}
# Restart=always

# [Install]
# WantedBy=network-online.target
# EOF

#     systemctl enable ${SERVICE}
#     systemctl restart ${SERVICE}
}

proxy() {
    echo TODO
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
    if [ $UID != 0 ] && [ ! -v FORCE_RUN ]; then
        echo "Sorry ${USER}, you can only run this script as root."
        exit 1
    fi
    set -euo pipefail
    shopt -s extglob
    export PODMAN_TRAEFIK_SECRETS_DIR=${PODMAN_TRAEFIK_SECRETS_DIR:-/var/local/podman_traefik/secrets}
    if [ ! -d ${PODMAN_TRAEFIK_SECRETS_DIR} ]; then
        mkdir -p ${PODMAN_TRAEFIK_SECRETS_DIR}
        chmod 0700 ${PODMAN_TRAEFIK_SECRETS_DIR}
    fi
    unset init
}

init
