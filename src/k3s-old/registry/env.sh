### registry env
source util.sh

## Lists of template variable names.
## Unspecified/commented vars from these lists, will be queried for input during render.
## ALL_VARS is the names of all of variables passed to the templates:
## ALL_SECRETS is the names of the variables to store in sealed secret:
export ALL_VARS=(IMAGE DOMAIN HTPASSWD_REALM)
export ALL_SECRETS=(ADMIN_USER ADMIN_PASSWORD HTPASSWD HA_SHARED_SECRET \
                    S3_ACCESS_KEY S3_SECRET_KEY S3_REGION S3_ENDPOINT S3_BUCKET)
## The object name for the secret:
export SECRET="registry"


## set vars, any vars commented out are interactivly input during render script.
export IMAGE=registry:2
#export DOMAIN=registry.k3s.example.com
export ADMIN_USER=admin

## Basic Auth Realm:
export HTPASSWD_REALM="Registry Realm"

## Generate passwords:
if [[ ! -f ${SECRET}.sealed_secret.yaml ]]; then
    ADMIN_PASSWORD=$(gen_password)
    echo "OK: Generated password for ${ADMIN_USER}: ${ADMIN_PASSWORD}"
    export HTPASSWD=$(htpasswd ${ADMIN_USER} ${ADMIN_PASSWORD})
    check_length 50 HTPASSWD

    export HA_SHARED_SECRET=$(gen_password)
    check_length 50 HA_SHARED_SECRET
fi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/registry/registry.configmap.template.yaml
    $TEMPLATE_SRC/registry/registry.template.yaml
    $TEMPLATE_SRC/registry/registry.ingress.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=()
