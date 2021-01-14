#!/bin/bash
## Podman systemd and container config with Traefik, for Ubuntu 20.10 by EnigmaCurry.
## This is a wrapper script that creates another script at ${SCRIPT_INSTALL_PATH}.
##   ( /usr/local/sbin/podman_traefik.sh by default )
## The new installed script will have hard-coded the configuration gathered by
## this wrapper script. If you need to update the config, edit the new script,
## and re-run.

core_config() {
    # Podman and Traefik config.
    ## Permanent install path for the new script:
    DEFAULT_SCRIPT_INSTALL_PATH=/usr/local/sbin/podman_traefik.sh

    ## Traefik:
    DEFAULT_TLS_ON=true
    DEFAULT_DOMAIN=dev1.example.com
    DEFAULT_ACME_EMAIL=you@example.com
    DEFAULT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory

    ## Create array of all config variable names:
    ## Other configs may also add to this list:
    ALL_VARS=( SCRIPT_INSTALL_PATH \
               TLS_ON \
               DOMAIN \
               ACME_EMAIL \
               ACME_CA )
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
    ## Do the header first, which includes config:
    cat <<'END_OF_SCRIPT_HEADER' > ${SCRIPT_INSTALL_PATH}
#!/bin/bash -ex
## Podman systemd config for Ubuntu 20.10

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

    cat <<'END_OF_INSTALLER' >> ${SCRIPT_INSTALL_PATH}
}


install() {
    ## Create /etc/sysconfig to store container environment files
    mkdir -p /etc/sysconfig

    ## Install packages:
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get -y install podman runc

    ## Niceties:
    echo "set enable-bracketed-paste on" >> /root/.inputrc
}

write_container_service() {
    ## Template for a podman container systemd unit
    ## Expects environment file at /etc/sysconfig/${SERVICE}
    SERVICE=$1
    IMAGE=$2
    PODMAN_ARGS=$3
    CMD_ARGS=${@:4}
    cat <<EOF > /etc/systemd/system/${SERVICE}.service
[Unit]
After=network-online.target

[Service]
EnvironmentFile=/etc/sysconfig/${SERVICE}
ExecStartPre=-/usr/bin/podman rm -f ${SERVICE}
ExecStart=/usr/bin/podman run --name ${SERVICE} --rm --env-file /etc/sysconfig/${SERVICE} ${PODMAN_ARGS} ${IMAGE} ${CMD_ARGS}
ExecStop=/usr/bin/podman stop ${SERVICE}
SyslogIdentifier=${SERVICE}
Restart=always

[Install]
WantedBy=network-online.target
EOF
}

traefik_service() {
    SERVICE=traefik
    IMAGE=traefik:v2.3
    touch /etc/sysconfig/${SERVICE}
    mkdir /etc/sysconfig/${SERVICE}.d
    write_container_service \
      ${SERVICE} ${IMAGE} "-v /etc/sysconfig/${SERVICE}.d:/etc/traefik/" \
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
  storage = "/etc/traefik/acme/acme.json"
  tlschallenge=true
  caserver=${ACMA_CA}
  email=${ACME_EMAIL}
END_TRAEFIK_CONF

    systemctl enable --now ${SERVICE}
}

main() {
    if [ ${UID} != 0 ]; then
        echo "Run this as root."
        exit 1
    fi
    default_config
    config
    install
    traefik_service
    postgres_service
    phoenix_service
    chmod go-rwx -R /etc/sysconfig
    echo "All done :)"
}

main
END_OF_INSTALLER

    echo "## Script written to ${SCRIPT_INSTALL_PATH}"
}

main() {
    # Run core config first:
    core_config
    # Run each application config function next:
    for var in "${ALL_CONFIGS[@]}"; do
        $var
    done
    # Merge all the configs, applying environment vars first, then the defaults:
    merge_config
    # Create the new install script, with all of the config hard-coded:
    create_script
    # Run the new install script:
    ${SCRIPT_INSTALL_PATH}
}

