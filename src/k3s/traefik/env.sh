### User defined variables:
## Host port for Traefik/HTTP
export HTTP_PORT=80
## Host port for Traefik/HTTP+TLS
export HTTPS_PORT=443
## Host port for Traefik/TCP+SSH
export SSH_PORT=2222
## Email should be your own personal/work email address, sent to Lets Encrypt
export ACME_EMAIL='you@example.com'
## The CA server - use 'acme-staging-v02' for staging and 'acme-v02' for prod
export ACME_SERVER='https://acme-staging-v02.api.letsencrypt.org/directory'
## The size of the volume for Traefik ACME storage (1Gi is often the smallest avail)
export ACME_PVC_SIZE=1Gi
## Domain name to use for the new whoami service
export WHOAMI_DOMAIN='whoami.k3s.example.com'

## Vars for render.sh functionality:
## Required env vars list enforced by render.sh
export ENV_VARS=(TEMPLATES HTTP_PORT HTTPS_PORT SSH_PORT ACME_EMAIL ACME_SERVER ACME_PVC_SIZE WHOAMI_DOMAIN)
## Template source directory or http path
TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
## YAML Template URLs
export TEMPLATES=(
    $TEMPLATE_SRC/traefik/traefik.pvc.template.yaml
    $TEMPLATE_SRC/traefik/traefik.template.yaml
    $TEMPLATE_SRC/traefik/whoami.template.yaml
)
