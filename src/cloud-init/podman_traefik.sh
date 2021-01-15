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
    SERVICE=$1
    IMAGE=$2
    PODMAN_ARGS="-l podman_traefik $3"
    CMD_ARGS=${@:4}
    touch /etc/sysconfig/${SERVICE}
    cat <<EOF > /etc/systemd/system/${SERVICE}.service
[Unit]
After=network-online.target

[Service]
ExecStartPre=-/usr/bin/podman rm -f ${SERVICE}
ExecStart=/usr/bin/podman run --name ${SERVICE} --rm --env-file /etc/sysconfig/${SERVICE} ${PODMAN_ARGS} ${IMAGE} ${CMD_ARGS}
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
    TRAEFIK_SERVICE=traefik
    SERVICE=$1
    DOMAIN=$2
    PORT=${3:-80}
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
  tls = "true"
  [http.routers.${SERVICE}-secure.tls]
    certresolver = "default"
[[http.services.${SERVICE}.loadBalancer.servers]]
  address = "http://${SERVICE}:${PORT}/"
END_PROXY_CONF
}


wrapper() {
    core_config() {
        # Podman and Traefik config.
        ## Permanent install path for the new script:
        DEFAULT_SCRIPT_INSTALL_PATH=/usr/local/sbin/podman_traefik.sh

        ## Traefik:
        DEFAULT_TRAEFIK_IMAGE=traefik:v2.3
        DEFAULT_ACME_EMAIL=you@example.com
        DEFAULT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory

        ## Required output variables:
        ##  - Create array of all TEMPLATES (functions) for this config:
        ##  - Create array of all config VARS from this config:
        TEMPLATES=(traefik_service)
        VARS=( SCRIPT_INSTALL_PATH \
               TRAEFIK_IMAGE \
               ACME_EMAIL \
               ACME_CA )
    }

    traefik_service() {
        SERVICE=traefik
        IMAGE=${TRAEFIK_IMAGE}
        NETWORK_ARGS="--network web -p 80:80 -p 443:443"
        VOLUME_ARGS="-v /etc/sysconfig/${SERVICE}.d:/etc/traefik/"
        mkdir -p /etc/sysconfig/${SERVICE}.d
        podman network create web
        create_service_container \
            ${SERVICE} ${IMAGE} \
            "${NETWORK_ARGS} ${VOLUME_ARGS}" \
            --providers.file.directory=/etc/traefik \
            --providers.file.watch=true

        cat <<END_TRAEFIK_CONF > /etc/sysconfig/${SERVICE}.d/traefik.toml
[log]
  level = "DEBUG"
[api]
  insecure = false
  dashboard = false
[entrypoints]
  [entrypoints.web]
    address = ":80"
    [entrypoints.web.http.redirections.entrypoint]
      to = "websecure"
      scheme = "https"
  [entrypoints.websecure]
    address = ":443"
[certificatesResolvers.default.acme]
  storage = "/etc/traefik/acme.json"
  tlschallenge = true
  caserver = "${ACME_CA}"
  email = "${ACME_EMAIL}"
END_TRAEFIK_CONF

        systemctl enable --now ${SERVICE}
    }


    merge_config() {
        ## load variables from the environment, or use the DEFAULT if unspecified:
        # This is to be run after all all other configs have added vars to ALL_VARS
        echo "## Config:"
        for var in "${ALL_VARS[@]}"; do
            default_name=DEFAULT_$var
            default_value=${!default_name}
            value=${!var:-$default_value}
            declare -g $var=$value
            echo $var=${!var}
        done
    }

    create_script() {
        ## Save config in permanent script:
        touch ${SCRIPT_INSTALL_PATH} && chmod 0700 ${SCRIPT_INSTALL_PATH}
        ## Do the header first, which includes hard-coded config:
        cat <<'END_OF_SCRIPT_HEADER' > ${SCRIPT_INSTALL_PATH}
#!/bin/bash -eux
## Podman systemd config

## Default values that were used during first install:
default_config() {
END_OF_SCRIPT_HEADER

        for var in "${ALL_VARS[@]}"; do
            echo "    DEFAULT_$var=${!var}" >> ${SCRIPT_INSTALL_PATH}
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
    apt-get install -y dnsmasq
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
    chmod go-rwx -R /etc/sysconfig
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
        TEMPLATES=()
        VARS=()
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
