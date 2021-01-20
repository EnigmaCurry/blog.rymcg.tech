#!/bin/bash
## This is like docker-compose, except it's just podman and bash.
(
    set -euxo pipefail
    ## Create directory for all config scripts:
    mkdir -p /etc/podman_traefik.d

    ## Create the core config script:
    ## Edit ACME_EMAIL and ACME_CA for Traefik.
    cat <<'EOF' > /etc/podman_traefik.d/core.sh
#!/bin/bash
## Podman_Traefik Config:
export ACME_EMAIL=you@example.com
export ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
export PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
EOF


    ## Create the whoami service config file:
    ## Edit WHOAMI_DOMAIN for your domain name.
    cat <<'EOF' > /etc/podman_traefik.d/whoami.sh
#!/bin/bash
## whoami config:
export WHOAMI_DOMAIN=whoami.podman.rymcg.tech

whoami() {
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    TEMPLATES=(whoami_service)
    VARS=(WHOAMI_DOMAIN)
}
whoami_service() {
    local SERVICE=whoami
    local IMAGE=traefik/whoami
    local RANDOM_NAME=whoami-$(openssl rand -hex 3)
    local PODMAN_ARGS="--network web"
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" \
                             -port 8080 -name ${RANDOM_NAME}
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 8080
    systemctl enable ${SERVICE}
    systemctl restart ${SERVICE}
}
EOF

    ## Create the install script:
    cat <<'EOF' > /etc/podman_traefik.sh
#!/bin/bash

## Podman Traefik install script
## Configs are found in separate shell scripts in /etc/podman_traefik.d
## One of them (core.sh) must define PODMAN_TRAEFIK_SCRIPT url.
## NOTE: There is only one namespace (shell environment) for all configs.
## ALL variables and function names must be unique!

(
    ## Find all the configs and then run the install script from the URL:
    set -euxo pipefail
    export ALL_CONFIGS=()
    for conf in $(ls /etc/podman_traefik.d/*.sh); do
        source ${conf}
        filename=$(basename ${conf})
        name="${filename%.*}"
        ALL_CONFIGS+=(${name})
    done
    if ! which curl; then
      apt-get update && apt-get install -y curl
    fi
    source <(wget -O - ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
EOF

    ## Run install script:
    chmod 0700 /etc/podman_traefik.sh
    /etc/podman_traefik.sh
)
