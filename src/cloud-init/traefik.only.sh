#!/bin/bash
(
    set -euxo pipefail
    ## Create directory for all config scripts:
    mkdir -p /etc/podman_traefik.d

    ## Create the core config script:
    ## Edit ACME_EMAIL and ACME_CA for Traefik.
    cat <<'EOF' > /etc/podman_traefik.d/core.sh
#!/bin/bash
## Podman_Traefik Config:
export ACME_EMAIL=letsencrypt@enigmacurry.com
export ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
export PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
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
    source <(wget -O - ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
EOF

    ## Run install script:
    chmod 0700 /etc/podman_traefik.sh
    /etc/podman_traefik.sh
)
