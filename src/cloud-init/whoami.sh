#!/bin/bash
## podman_traefik example whoami service by EnigmaCurry for Ubuntu 20.10.
## This is like docker-compose, except it's just podman and bash. This is
## cloud-init supported: it does the full podman install from a clean Ubuntu
## 20.10 node, installs Traefik as a TLS reverse proxy, and configures the
## `whoami` service as a test web server. Systemd runs each container as a
## seperate unit, with a service file generated via template based on your
## config. This script outputs config files to `/etc/podman_traefik.d/` which
## you can add additional config files to later. This wrapper script exports
## another script called `/etc/podman_traefik.sh` which you can run anytime to
## re-generate all of your configs. You have to edit a few variables in this
## current script before you run this, READ THE COMMENTS:
(
    set -euxo pipefail
    ## This creates the directory for all config scripts:
    ## Script files, ending in .sh will be auto-sourced from this directory:
    ## Note that all non-local variables and function names must be unique!
    mkdir -p /etc/podman_traefik.d

    ## This creates the core config script:
    ## Edit ACME_EMAIL and ACME_CA for Traefik
    cat <<'EOF' > /etc/podman_traefik.d/traefik.sh
#!/bin/bash
# Edit your ACME_EMAIL address to register with Let's Encrypt
export ACME_EMAIL=you@example.com
# Edit ACME_CA if you want to generate a valid TLS cert (remove `-staging`)
export ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
EOF

    ## Create the whoami service config file:
    ## Edit WHOAMI_DOMAIN
    cat <<'EOF' > /etc/podman_traefik.d/whoami.sh
#!/bin/bash
## Edit WHOAMI_DOMAIN for your real domain name:
export WHOAMI_DOMAIN=whoami.example.com

whoami() {
    ## Just sets up variables for the whoami templates.
    ## This links to one or several TEMPLATE functions to run.
    ## Leave DEFAULT vars alone, its meant as a permanent example.
    ## if WHOAMI_DOMAIN is undefined, DEFAULT_WHOAMI_DOMAIN is used instead.
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    ## TEMPLATES and VARS are required variables in all configs:
    ## TEMPLATES is a list (array) of template functions to call.
    ## VARS is a list (array) of variables to pass to the templates.
    TEMPLATES=(whoami_service)
    ## variables from outside environment override DEFAULT values with same name
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
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" \
                             -port 8080 -name ${RANDOM_NAME}
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
