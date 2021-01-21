#!/bin/bash

## Imaginary DSL to podman_traefik as an SSH bomb to a remote server:

# Install the tool on the remote host:
ssh podman.example.com /bin/bash <(curl -Lo $PODMAN_TRAEFIK_INSTALLER)

# Create local service description:
cat <<'EOF' > wordpress.sh
traefik ACME_EMAIL=you@example.com
environ wordpress \
    WORDPRESS_DB_HOST=wordpress_db \
    WORDPRESS_DB_NAME=wordpress \
    WORDPRESS_DB_USER=wordpress \
    WORDPRESS_DB_PASSWORD=$(password WORDPRESS_DB_PASSWORD)
environ wordpress_db \
    MYSQL_DATABASE=wordpress
    MYSQL_USER=wordpress
    MYSQL_PASSWORD=$(password WORDPRESS_DB_PASSWORD) \
    MYSQL_ROOT_PASSWORD=$(password WORDPRESS_MYSQL_ROOT_PASSWORD)
container wordpress_db mariadb:10.4 \
  "-v wordpress_db:/var/lib/mariadb --network wordpress"
container wordpress wordpress:latest \
  "--network web --network wordpress"
proxy wordpress blog.example.com 80
EOF

ssh podman.example.com podman_traefik < wordpress.sh
