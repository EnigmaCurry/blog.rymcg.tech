#!/bin/bash
## App Config:
local WHOAMI_DOMAIN=whoami.example.com
## Podman_Traefik Config:
ACME_EMAIL=you@example.com
ALL_CONFIGS=(whoami_config)
ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
local PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
########

whoami_config() {
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
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
