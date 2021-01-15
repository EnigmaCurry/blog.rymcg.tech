#!/bin/bash

## This script will install podman, traefik, and the whoami service.
## Use Ubuntu >= 20.04, run this as root, or from cloud-init.
## This imports podman_traefik.sh from this URL:
PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/podman-cloud-init/src/cloud-init/podman_traefik.sh

## Main config (you should change these):
## any vars commented out will use the DEFAULT variable from the script instead.

# The domain name to use for the whoami service:
# Also set a DNS `A` record pointed to the server's IP address for this domain:
WHOAMI_DOMAIN=whoami.example.com

# Your email address to register with Let's Encrypt (example.com will NOT work):
ACME_EMAIL=you@example.com

# The ACME Certificate Authority (Default is to use Let's Encrypt PRODUCTION.)
# Uncomment this ACME_CA to use the Let's Encrypt STAGING server instead:
#ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory

### END USER CONFIG
### Everything below this line is for developers only:
##
##
##
##

## ALL_CONFIGS is a list of all of the config functions in this script.
## ALL_CONFIGS is passed to the podman_traefik script to run.
ALL_CONFIGS=(whoami_config)

whoami_config() {
    ## Default vars:
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com

    ## Required output vars:
    # TEMPLATES is a list (array) of functions to run to create the service(s)
    TEMPLATES=(whoami_service)
    # VARS is a list (array) of all the variable NAMES used in this config
    VARS=(WHOAMI_DOMAIN)
}

whoami_service() {
    # Note all of the variable names in this function are for convenience only.
    # You can name them whatever you want or use none at all.
    SERVICE=whoami
    IMAGE=traefik/whoami

    # RANDOM_NAME is a random name given to whoami that changes each time you
    # re-install:
    # (it stays the same if the container just restarts without being re-installed)
    RANDOM_NAME=whoami-$(openssl rand -hex 3)

    # PODMAN_ARGS is any additional arguments needed to pass to `podman run`.
    # Use this to map volumes or ports etc. `--network web` adds it to the same
    # network as Traefik, allowing it to be proxied:
    PODMAN_ARGS="--network web"

    # create_service_container is a function that comes from the podman_traefik script.
    # It takes 4+ arguments: SERVICE IMAGE PODMAN_ARGS [CMD_ARG1, CMD_ARG2, ... ]
    # PODMAN_ARGS must be wrapped in quotes as shown:
    # CMD_ARGS is everything from argument 4 onwards (-name ${RANDOM_NAME}):
    create_service_container ${SERVICE} ${IMAGE} \"${PODMAN_ARGS}\" -name ${RANDOM_NAME}

    # create_service_proxy will create a public web proxy for whoami through traefik:
    # It takes 2+ arguments: SERVICE DOMAIN [CONTAINER_PORT]
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 80

    # start the service now:
    systemctl enable --now ${SERVICE}
}

## Get podman_traefik template and run it:
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    ## Run wrapper:
    wrapper
)
