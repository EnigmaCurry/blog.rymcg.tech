### gitea environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(IMAGE PVC_SIZE POSTGRES_PVC_SIZE DOMAIN APP_NAME SSH_PORT \
                 DISABLE_REGISTRATION DISABLE_GIT_HOOKS REQUIRE_SIGNIN_VIEW \
                 START_SSH_SERVER)

## All secrets are input at *render* time, and made into sealed secret(s).
export SECRET="gitea"
## List of the *names* of all of the secret variables to ask for:
## Variables not defined are interactively asked for.
## Variables that are defined, are used as-is.
export ALL_SECRETS=(POSTGRES_USER POSTGRES_PASSWORD INTERNAL_TOKEN \
                    JWT_SECRET SECRET_KEY)

## Container image
export IMAGE=gitea/gitea:latest
## Domain name for UI and clone URLs
export DOMAIN="git.k3s.example.com"
## UI title
export APP_NAME="${DOMAIN}"
## Start SSH service (or not)
export START_SSH_SERVER="true"
## SSH PORT (external; from traefik)
export SSH_PORT="2222"
## Enable or disable registration:
export DISABLE_REGISTRATION="true"
## Allow git hooks for users with Git Hooks permission.
export DISABLE_GIT_HOOKS="false"
## Require sign-in
export REQUIRE_SIGNIN_VIEW="true"
## Size of data volume:
export PVC_SIZE=5Gi
## Size of database volume:
export POSTGRES_PVC_SIZE=5Gi
## postgres user account
export POSTGRES_USER=gitea

## Generate tokens/keys:
if [[ ! -f gitea.sealed_secret.yaml ]]; then
    export POSTGRES_PASSWORD=$(tr -dc '[:alnum:]' < /dev/urandom | dd bs=4 count=8 2>/dev/null)
    echo "Generating gitea tokens/keys ... "
    ## INTERNAL_TOKEN is a "Secret used to validate communication within Gitea binary"
    ## This is regenerated each time this is rendered, and put into Sealed Secret.
    ## Call the gitea binary in a temporary container:
    export INTERNAL_TOKEN=$(kubectl run --quiet -i --rm --tty gitea-keygen-$RANDOM --image=gitea/gitea:latest --restart=Never -- /usr/local/bin/gitea generate secret INTERNAL_TOKEN 2> /dev/null)
    if [[ $(echo $INTERNAL_TOKEN | wc -c) -lt 50 ]]; then
        echo "Error generating INTERNAL_TOKEN"
        echo "Token was: "$INTERNAL_TOKEN
        exit 1
    fi
    ## JWT_SECRET is a "LFS & OAUTH2 JWT authentication secret"
    ## This is regenerated each time this is rendered, and put into Sealed Secret.
    ## Call the gitea binary in a temporary container:
    export JWT_SECRET=$(kubectl run --quiet -i --rm --tty gitea-keygen-$RANDOM --image=gitea/gitea:latest --restart=Never -- /usr/local/bin/gitea generate secret JWT_SECRET 2> /dev/null)
    if [[ $(echo $JWT_SECRET | wc -c) -lt 25 ]]; then
        echo "Error generating JWT_SECRET"
        exit 1
    fi
    ## SECRET_KEY is the "Global secret key"
    ## This is regenerated each time this is rendered, and put into Sealed Secret.
    ## Call the gitea binary in a temporary container:
    export SECRET_KEY=$(kubectl run --quiet -i --rm --tty gitea-keygen-$RANDOM --image=gitea/gitea:latest --restart=Never -- /usr/local/bin/gitea generate secret SECRET_KEY 2> /dev/null)
    if [[ $(echo $SECRET_KEY | wc -c) -lt 50 ]]; then
        echo "Error generating SECRET_KEY"
        exit 1
    fi
fi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/gitea/gitea.postgres.pvc.template.yaml
    $TEMPLATE_SRC/gitea/gitea.postgres.template.yaml
    $TEMPLATE_SRC/gitea/gitea.pvc.template.yaml
    $TEMPLATE_SRC/gitea/gitea.template.yaml
    $TEMPLATE_SRC/gitea/gitea.ingress.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=(
    $TEMPLATE_SRC/gitea/app.template.ini
)
