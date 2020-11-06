### gitea environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(POSTGRES_PVC_SIZE POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD)
## Size of database:
export POSTGRES_PVC_SIZE=5Gi
## TCP port
export POSTGRES_PORT=5432
## Database username
export POSTGRES_USER=gitea
## Database password (stored in secret `postgres.password`):
## (Must be base64 encoded before put in Secret)
export POSTGRES_PASSWORD=$(echo -n "changeme" | base64)

## render.sh functionality:
## Required env vars list enforced by render.sh
## Default template source directory, or http path:
TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/gitea/postgres.pvc.template.yaml
    $TEMPLATE_SRC/gitea/postgres.secret.template.yaml
    $TEMPLATE_SRC/gitea/postgres.template.yaml
)
