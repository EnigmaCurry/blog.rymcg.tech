#!/bin/bash
## podman_traefik example cloud-init script by EnigmaCurry for Ubuntu 20.10.

## This is like docker-compose, except it's just podman and bash. This is
## cloud-init supported: it does the full podman install from a clean Ubuntu
## 20.10 node, it installs Traefik as a TLS reverse proxy, and it configures the
## `whoami` service as a test web server. Systemd runs each container as a
## separate unit, with a service file generated via template, based on your
## config. This script outputs config files to `/etc/podman_traefik.d/` which
## you can add additional config files to later. This wrapper script exports
## another script called `/etc/podman_traefik.sh` which you can run anytime to
## re-generate all of your configs. You have to edit a few variables in this
## current script before you run this, READ THE COMMENTS. The full documentation
## for this script is contained in this file, and others which are linked from
## this one. You can use this file as the basis for your own scripts, and that
## way you'll have the full documentation with you at all times.

## For this example, you must edit: TRAEFIK_ACME_EMAIL, TRAEFIK_ACME_CA, and
## WHOAMI_DOMAIN. I've marked all the places you need to edit with the tag
## `EDIT:`, just search for it.

## Once this script is edited, copy it to your cloud-init service provider and
## create your node. You could use DigitalOcean for this, and paste this whole script
## into the `User data` section on their droplet creation screen, and everything
## will be installed automatically on the node when created.

## Important files and directories created by this script:
##  /etc/podman_traefik.sh    - script to regenerate configs, restart services
##  /etc/podman_traefik.d/    - directory stores all YOUR configs (editable)
##  /etc/podman_traefik.d/traefik.sh - stores Traefik config including ACME vars
##  /etc/podman_traefik.d/whoami.sh - stores the whoami config from this example
##  /var/log/cloud-init-output.log - the log of this script run on first install
##  /etc/systemd/{container}.service - each container has a systemd service unit
##  /var/local/podman_traefik.sh - the 'compiled' config with no dependencies
##  /etc/sysconfig/ - stores the GENERATED conf for each container (don't edit)
##  /etc/sysconfig/{container}  - each container has an Environment file
##  /etc/sysconfig/traefik.d  - GENERATED Traefik config is loaded here

## Important environment variables:
##  WHOAMI_DOMAIN - the domain name the whoami service responds to
##  TRAEFIK_ACME_EMAIL - your email address to register with Let's Encrypt
##  TRAEFIK_ACME_CA - the Let's Encrypt API URL (staging or production)
##  TRAEFIK_IMAGE - the traefik docker container image name:tag
##  PODMAN_TRAEFIK_FIRST_TIME - You can check for the existance of this variable
##    in order to know whether this is the first time the script is being run.
##    You can use this to generate passwords and tokens on the first install
##    only, but skipped when re-configuring. It is indicated when
##    `/var/local/podman_traefik.sh` exists (written by this script).
##  DEFAULT(s), TEMPLATES, and VARS - Each config function has three jobs:
##    1) Define all DEFAULT variables for the particular service.
##    2) Make a list of template functions called TEMPLATES.
##    3) Make a list of variable names called VARS to pass to TEMPLATES.
##  DEFAULT variables are only used if the non-default variable is undefined.

## Quick systemd tutorial:
##  Check status:     systemctl status ${SERVICE_NAME}
##  Check logs:       journalctl -u ${SERVICE_NAME}
##  Restart:          systemctl restart ${SERVICE_NAME}

## OK Let's go
(
    ## Immediately quit the script if there is any error:
    set -euxo pipefail
    ## This creates the directory for all config scripts:
    ## Script files, ending in .sh, will be auto-sourced from this directory:
    ## Note that all non-local variables and function names must be unique!
    mkdir -p /etc/podman_traefik.d
    chmod 0700 /etc/podman_traefik.d

    # EDIT: TRAEFIK_ACME_EMAIL is your email address to register with Let's Encrypt
    export TRAEFIK_ACME_EMAIL=you@example.com
    # EDIT: TRAEFIK_ACME_CA if you want a production ready TLS cert
    #  (remove `-staging` or just comment out to use default production server)
    export TRAEFIK_ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
    export TRAEFIK_IMAGE=traefik:v2.3

    ## Create the whoami service config file:
    ## Edit WHOAMI_DOMAIN
    cat <<'EOF' > /etc/podman_traefik.d/whoami.sh
## EDIT: WHOAMI_DOMAIN for your real domain name:
export WHOAMI_DOMAIN=whoami.example.com

whoami() {
    ## Just sets up variables for the whoami templates.
    ## This links to one or several TEMPLATE functions to run.
    ## Leave DEFAULT vars alone, its meant as a permanent example.
    ## if WHOAMI_DOMAIN is undefined, DEFAULT_WHOAMI_DOMAIN is used instead.
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    ## TEMPLATES and VARS are required variables in all configs:
    ## TEMPLATES is a list (array) of template functions to call.
    TEMPLATES=(whoami_service)
    ## VARS is a list (array) of variables to pass to the templates.
    ## environment variables override DEFAULT values with same name:
    VARS=(WHOAMI_DOMAIN)
}
whoami_service() {
    ## whoami_service is a template function called from the TEMPLATES list.
    ## You can make other templates too, even source them from a URL, just add
    ## them to the TEMPLATES list.
    ## This template just creates one container, and sets up the proxy for it:
    local SERVICE=whoami
    local IMAGE=traefik/whoami
    local RANDOM_NAME=whoami-$(openssl rand -hex 3)
    local PODMAN_ARGS="--network web"
    ## create_service_container creates and starts containers in systemd units
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" \
                             -port 8080 -name ${RANDOM_NAME}
    ## create_service_proxy creates a traefik config for a container port
    ## container must be in same network as traefik (`--network web`)
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 8080
}
EOF

    ## Create the installer and run it:
    cat <<'EOF' > /etc/podman_traefik.sh
#!/bin/bash
(
    set -euxo pipefail
    # Link to EnigmaCurry's podman_traefik script, (or fork your own copy)
    ## Note this URL wraps two lines with `\` :
    PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/\
EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
    source <(wget -O - ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
EOF

    chmod 0700 /etc/podman_traefik.sh
    /etc/podman_traefik.sh
)

## THE END
