#!/bin/bash

## Imaginary BASH-powered DSL for Podman and Traefik, as an SSH bomb

cat <<'EOF' | ssh podman.example.com /bin/bash
source <(curl https://raw.githubusercontent.com/\
EnigmaCurry/blog.rymcg.tech/imagine/src/cloud-init/podman_traefik.imagine.sh)

## Install traefik service:
## Needs your email address to register account with Let's Encrypt
traefik ACME_EMAIL=you@example.com

## Create per-environment dictionaries (`declare -AA app1 app2 db1 ...`):
## (These are all of the environment vars needed to pass to containers)
## (Secrets are generated on the fly, then memoized by name)
declare -AA wordpress wordpress_db
wordpress[WORDPRESS_DB_HOST]=wordpress_db
wordpress[WORDPRESS_DB_NAME]=wordpress
wordpress[WORDPRESS_DB_USER]=wordpress
wordpress[WORDPRESS_DB_PASSWORD]=$(secret WORDPRESS_DB_PASSWORD)
wordpress_db[MYSQL_DATABASE]=wordpress
wordpress_db[MYSQL_USER]=wordpress
wordpress_db[MYSQL_PASSWORD]=$(secret WORDPRESS_DB_PASSWORD)
wordpress_db[MYSQL_ROOT_PASSWORD]=$(secret WORDPRESS_MYSQL_ROOT_PASSWORD)

## Create containers:
## Systemd units are (re)created, enabled on boot, and (re)started
container wordpress wordpress:latest \
  "--network web --network wordpress"
container wordpress_db mariadb:10.4 \
  "-v wordpress_db:/var/lib/mariadb --network wordpress"

## Create web proxy: forwards public HTTPS domain traffic to this container port
proxy wordpress blog.example.com 80
EOF

