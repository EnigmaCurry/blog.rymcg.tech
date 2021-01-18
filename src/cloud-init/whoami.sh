#!/bin/bash
PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
WHOAMI_DOMAIN=whoami.example.com
ACME_EMAIL=you@example.com
ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
ALL_CONFIGS=(whoami_config)
whoami_config() {
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    TEMPLATES=(whoami_service)
    VARS=(WHOAMI_DOMAIN)
}
whoami_service() {
    SERVICE=whoami
    IMAGE=traefik/whoami
    RANDOM_NAME=whoami-$(openssl rand -hex 3)
    PODMAN_ARGS="--network web"
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" -name ${RANDOM_NAME}
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 80
    systemctl enable --now ${SERVICE}
}
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
