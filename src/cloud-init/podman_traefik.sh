#!/bin/bash
## Podman systemd and container config with Traefik, for Ubuntu>=20.04 by EnigmaCurry.
## This is a wrapper script that creates another script at ${SCRIPT_INSTALL_PATH}.
##   ( /usr/local/sbin/podman_traefik.sh by default )
## The new installed script will have hard-coded the configuration gathered by
## this wrapper script. If you need to update the config after installation,
## edit the new script, and re-run.

## Don't use this script by itself. You should extend it instead.
## see whoami.sh for an example

create_service_container() {
    ## Template function to create a systemd unit for a podman container
    ## Expects environment file at /etc/sysconfig/${SERVICE}
    local SERVICE=$1
    local IMAGE=$2
    local PODMAN_ARGS="${BASE_PODMAN_ARGS} $3"
    local CMD_ARGS=${@:4}
    local SERVICE_USER=${SERVICE_USER:-podman-${SERVICE}}
    # Create environment file (required, but might stay empty)
    touch /etc/sysconfig/${SERVICE}
    # Create user account to run container:
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
}

create_service_proxy() {
    ## Template function to create a traefik configuration for a service.
    ## Creates automatic http to https redirect.
    ## Note: traefik will automatically reload configuration when the file changes.
    local TRAEFIK_SERVICE=traefik
    local SERVICE=$1
    local DOMAIN=$2
    local PORT=${3:-80}
    cat <<END_PROXY_CONF > /etc/sysconfig/${TRAEFIK_SERVICE}.d/${SERVICE}.toml
[http.routers.${SERVICE}]
  entrypoints = "web"
  rule = "Host(\"${DOMAIN}\")"
  middlewares = "${SERVICE}-secure-redirect"
[http.middlewares.${SERVICE}-secure-redirect.redirectscheme]
  scheme = "https"
  permanent = "true"
[http.routers.${SERVICE}-secure]
  entrypoints = "websecure"
  rule = "Host(\"${DOMAIN}\")"
  service = "${SERVICE}"
  [http.routers.${SERVICE}-secure.tls]
    certresolver = "default"
[[http.services.${SERVICE}.loadBalancer.servers]]
  url = "http://${SERVICE}:${PORT}/"
END_PROXY_CONF
}


wrapper() {
    core() {
        # Podman and Traefik config.
        ## Permanent install path for the new script:
        DEFAULT_SCRIPT_INSTALL_PATH=/usr/local/sbin/podman_traefik.sh
        DEFAULT_BASE_PODMAN_ARGS="-l podman_traefik --cap-drop ALL"
        ## Traefik:
        DEFAULT_TRAEFIK_IMAGE=traefik:v2.3
        DEFAULT_ACME_EMAIL=you@example.com
        DEFAULT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory

        ## Required output variables:
        ##  - Create array of all TEMPLATES (functions) for this config:
        ##  - Create array of all config VARS from this config:
        TEMPLATES=(traefik_service)
        VARS=( SCRIPT_INSTALL_PATH \
               BASE_PODMAN_ARGS \
               TRAEFIK_IMAGE \
               ACME_EMAIL \
               ACME_CA )
    }

    traefik_service() {
        local SERVICE=traefik
        local IMAGE=${TRAEFIK_IMAGE}
        local NETWORK_ARGS="--cap-add NET_BIND_SERVICE --network web -p 80:80 -p 443:443"
        local VOLUME_ARGS="-v /etc/sysconfig/${SERVICE}.d:/etc/traefik/"
        mkdir -p /etc/sysconfig/${SERVICE}.d/acme
        if ! podman network inspect web; then
            podman network create web
        fi
        SERVICE_USER=root create_service_container \
            ${SERVICE} ${IMAGE} \
            "${NETWORK_ARGS} ${VOLUME_ARGS}"

        cat <<END_TRAEFIK_CONF > /etc/sysconfig/${SERVICE}.d/traefik.toml
[log]
  level = "DEBUG"
[providers.file]
  directory = "/etc/traefik"
  watch = true
[entrypoints]
  [entrypoints.web]
    address = ":80"
    [entrypoints.web.http.redirections.entrypoint]
      to = "websecure"
      scheme = "https"
  [entrypoints.websecure]
    address = ":443"
[certificatesResolvers.default.acme]
  storage = "/etc/traefik/acme/acme.json"
  tlschallenge = true
  caserver = "${ACME_CA}"
  email = "${ACME_EMAIL}"
END_TRAEFIK_CONF

        systemctl enable ${SERVICE}
        systemctl restart ${SERVICE}
    }


    merge_config() {
        ## load variables from the environment, or use the DEFAULT if unspecified:
        # This is to be run after all all other configs have added vars to ALL_VARS
        echo "## Config:"
        for var in "${ALL_VARS[@]}"; do
            local default_name=DEFAULT_$var
            local default_value="${!default_name}"
            local value="${!var:-$default_value}"
            declare -g $var="${value}"
            echo $var="${!var}"
        done
    }

    create_script() {
        ## Save config in permanent script:
        touch ${SCRIPT_INSTALL_PATH} && chmod 0700 ${SCRIPT_INSTALL_PATH}
        ## Do the header first, which includes hard-coded config:
        cat <<END_OF_SCRIPT_HEADER > ${SCRIPT_INSTALL_PATH}
#!/bin/bash -eux
## Podman systemd config
## THIS IS A GENERATED FILE -
## Your changes will be overwritten if you reinstall podman_traefik.

## Default values that were used during first install:
ALL_TEMPLATES=(${ALL_TEMPLATES[@]})
default_config() {
END_OF_SCRIPT_HEADER

        for var in "${ALL_VARS[@]}"; do
            echo "    DEFAULT_$var=\"${!var}\"" >> ${SCRIPT_INSTALL_PATH}
        done

        cat <<'END_OF_SCRIPT_CONFIG' >> ${SCRIPT_INSTALL_PATH}
}

config() {
    ## This config overrides the default config, and is loaded from the outside
    ## environment variables. The names of the variables are the same as in the
    ## default config, except without the `DEFAULT_` prefix. If no such variable
    ## is provided, the default value is used instead.
    export HOME=${HOME:-/root}
END_OF_SCRIPT_CONFIG

        for var in "${ALL_VARS[@]}"; do
            echo "    $var=\${$var:-\$DEFAULT_$var}" >> ${SCRIPT_INSTALL_PATH}
        done

        cat <<END_DYNAMIC_CONFIG_1 >> ${SCRIPT_INSTALL_PATH}
}

$(declare -f create_service_container)

$(declare -f create_service_proxy)

END_DYNAMIC_CONFIG_1

        for template in "${ALL_TEMPLATES[@]}"; do
            cat <<END_DYNAMIC_CONFIG_2 >> ${SCRIPT_INSTALL_PATH}

$(declare -f ${template})

END_DYNAMIC_CONFIG_2
        done

        cat <<'END_OF_INSTALLER' >> ${SCRIPT_INSTALL_PATH}

install_packages() {
    ## Create /etc/sysconfig to store container environment files
    mkdir -p /etc/sysconfig

    ## Install packages:
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    systemctl mask dnsmasq.service
    apt-get install -y dnsmasq ufw
    ## Try to install podman, it should work in Ubuntu 20.10 + from regular repository:
    if ! apt-get -y install podman runc; then
        (
          source /etc/os-release
          if [ ${VERSION_ID} = '20.04' ]; then
            ## For Ubuntu 20.04 (LTS) need to install from Kubic project repositories:
            echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
            curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key | sudo apt-key add -
            apt-get update
            apt-get -y upgrade
            apt-get -y install podman
          else
            echo "Ubuntu ${VERSION_ID:-version Unknown} is unsupported. Sorry :("
          fi
        )
    fi

    ## Niceties:
    echo "set enable-bracketed-paste on" >> /root/.inputrc
}

(
    if [ ${UID} != 0 ]; then
        echo "Run this as root."
        exit 1
    fi
    default_config
    config
    install_packages
    for template in "${ALL_TEMPLATES[@]}"; do
      $template
    done
    chmod o-rwx -R /etc/sysconfig
    chmod g-w -R /etc/sysconfig
    chmod o+rx /etc/sysconfig
    echo "All done :)"
)
END_OF_INSTALLER

        echo "## Script written to ${SCRIPT_INSTALL_PATH}"
    }

    # Initialize list of all template functions
    ALL_TEMPLATES=()
    # Initialize list of all config variables
    ALL_VARS=()
    # Run all configs, core_config first:
    ALL_CONFIGS=(core_config ${ALL_CONFIGS[@]})
    for var in "${ALL_CONFIGS[@]}"; do
        local TEMPLATES=()
        local VARS=()
        ## Run the config (which sets TEMPLATES and VARS):
        $var
        ## Append templates and vars:
        ALL_TEMPLATES=(${ALL_TEMPLATES[@]} ${TEMPLATES[@]})
        ALL_VARS=(${ALL_VARS[@]} ${VARS[@]})
    done
    echo "ALL_TEMPLATES=${ALL_TEMPLATES[@]}"
    echo "ALL_VARS=${ALL_VARS[@]}"
    # Merge all the configs, applying environment vars first, then the defaults:
    merge_config
    # Create the new install script, with all of the config hard-coded:
    create_script
    # Run the new install script:
    ${SCRIPT_INSTALL_PATH}
}

## THE END
 
