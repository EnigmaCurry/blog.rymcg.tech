### drone env
source util.sh

## Lists of template variable names.
## Unspecified/commented vars from these lists, will be queried for input during render.
## ALL_VARS is the names of all of variables passed to the templates:
## ALL_SECRETS is the names of the variables to store in sealed secret:
export ALL_VARS=(IMAGE PVC_SIZE DOMAIN DRONE_GIT_ALWAYS_AUTH)
export ALL_SECRETS=(DRONE_GITEA_CLIENT_ID DRONE_GITEA_CLIENT_SECRET \
                    DRONE_GITEA_SERVER DRONE_SERVER_HOST DRONE_RPC_SECRET)
## The object name for the secret:
export SECRET="drone"

export IMAGE=drone/drone:1
#export DOMAIN=drone.k3s.example.com
export PVC_SIZE=10Gi
export DRONE_GIT_ALWAYS_AUTH=true
#export DRONE_GITEA_SERVER=https://gitea.k3s.example.com
#export DRONE_SERVER_HOST=drone.k3s.example.com


## Generate passwords:
if [[ ! -f ${SECRET}.sealed_secret.yaml ]]; then
    export DRONE_RPC_SECRET=$(gen_password)
    check_length 50 DRONE_RPC_SECRET
    echo "OK: Generated DRONE_RPC_SECRET: ${DRONE_RPC_SECRET}"
fi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/drone/drone.pvc.template.yaml
    $TEMPLATE_SRC/drone/drone.ingress.template.yaml
    $TEMPLATE_SRC/drone/drone.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=()
