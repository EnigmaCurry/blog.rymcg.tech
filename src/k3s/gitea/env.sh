### gitea environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(POSTGRES_PVC_SIZE POSTGRES_PORT)

## All secrets are input at *render* time, and made into a sealed secret.
## The name of the sealed secret to create:
export SECRET=gitea
## List of the *names* of all of the secret variables to ask for:
export ALL_SECRETS=(postgres_user postgres_password)

## Size of database:
export POSTGRES_PVC_SIZE=5Gi
## TCP port
export POSTGRES_PORT=5432

## Default template source directory, or http path:
TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/gitea/gitea.postgres.pvc.template.yaml
    $TEMPLATE_SRC/gitea/gitea.postgres.template.yaml
)
