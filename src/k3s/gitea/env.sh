### gitea environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(IMAGE PVC_SIZE POSTGRES_PVC_SIZE DOMAIN APP_NAME SSH_PORT \
                DISABLE_REGISTRATION REQUIRE_SIGNIN_VIEW)

## All secrets are input at *render* time, and made into a sealed secret.
## The name of the sealed secret to create:
export SECRET=gitea
## List of the *names* of all of the secret variables to ask for:
export ALL_SECRETS=(secret_key postgres_user postgres_password)

## Container image
export IMAGE=gitea/gitea:latest
## Domain name for UI and clone URLs
export DOMAIN="git.k3s.example.com"
## UI title
export APP_NAME="${DOMAIN}"
## SSH PORT (external; from traefik)
export SSH_PORT="2222"
## Enable or disable registration:
export DISABLE_REGISTRATION="true"
## Require sign-in
export REQUIRE_SIGNIN_VIEW="true"
## Size of data volume:
export PVC_SIZE=5Gi
## Size of database volume:
export POSTGRES_PVC_SIZE=5Gi

## Default template source directory, or http path:
TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/gitea/gitea.postgres.pvc.template.yaml
    $TEMPLATE_SRC/gitea/gitea.postgres.template.yaml
    $TEMPLATE_SRC/gitea/gitea.pvc.template.yaml
    $TEMPLATE_SRC/gitea/gitea.template.yaml
)
