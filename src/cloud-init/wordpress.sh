#!/bin/bash
## podman_traefik example: wordpress + mariadb + S3 backup
## see whoami.sh for a commented example
(
    set -euxo pipefail
    mkdir -p /etc/podman_traefik.d
    chmod 0700 /etc/podman_traefik.d

    export TRAEFIK_ACME_EMAIL=you@example.com
    export TRAEFIK_ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
    export TRAEFIK_IMAGE=traefik:v2.3

    cat <<'EOF' > /etc/podman_traefik.d/wordpress.sh
export WORDPRESS_DOMAIN=blog.podman.rymcg.tech

wordpress() {
    DEFAULT_WORDPRESS_DOMAIN=blog.example.com
    DEFAULT_WORDPRESS_MYSQL_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
    DEFAULT_WORDPRESS_MYSQL_ROOT_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
    TEMPLATES=(wordpress_service)
    VARS=(WORDPRESS_DOMAIN WORDPRESS_MYSQL_PASSWORD WORDPRESS_MYSQL_ROOT_PASSWORD)
}
wordpress_service() {
    if [[ -v PODMAN_TRAEFIK_FIRST_TIME ]]; then
        cat <<END_OF_ENVIRONMENT > /etc/sysconfig/wordpress
WORDPRESS_DB_HOST=wordpress_db
WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=${WORDPRESS_MYSQL_PASSWORD}
END_OF_ENVIRONMENT
        cat <<END_OF_ENVIRONMENT > /etc/sysconfig/wordpress_db
MYSQL_DATABASE=wordpress
MYSQL_USER=wordpress
MYSQL_PASSWORD=${WORDPRESS_MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${WORDPRESS_MYSQL_ROOT_PASSWORD}
END_OF_ENVIRONMENT
    fi

    create_service_container wordpress_db mariadb:10.4 \
      "-v wordpress_db:/var/lib/mariadb --network wordpress"

    create_service_container wordpress wordpress:latest \
      "--network web --network wordpress"
    create_service_proxy wordpress ${WORDPRESS_DOMAIN} 80

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

