### drone env
source util.sh

## Lists of template variable names.
## Unspecified/commented vars from these lists, will be queried for input during render.
## ALL_VARS is the names of all of variables passed to the templates:
## ALL_SECRETS is the names of the variables to store in sealed secret:
export ALL_VARS=(DRONE_IMAGE RUNNER_IMAGE DIGITALOCEAN_RUNNER_IMAGE \
                 SECRETS_EXTENSION_IMAGE PVC_SIZE \
                 DOMAIN DRONE_GIT_ALWAYS_AUTH NAMESPACE \
                 SSH_PRIVATE_KEY SSH_PUBLIC_KEY)
export ALL_SECRETS=(DRONE_GITEA_CLIENT_ID DRONE_GITEA_CLIENT_SECRET \
                    DRONE_GITEA_SERVER DRONE_SERVER_HOST DRONE_RPC_SECRET \
                    REGISTRY_DOMAIN REGISTRY_USER REGISTRY_PASSWORD \
                    DIGITALOCEAN_API_TOKEN DRONE_KUBERNETES_SECRET_KEY)
## The object name for the secret:
export SECRET="drone"

export NAMESPACE=drone
export DRONE_IMAGE=drone/drone:1
export RUNNER_IMAGE=drone/drone-runner-kube:latest
export DIGITALOCEAN_RUNNER_IMAGE=drone/drone-runner-digitalocean:latest
export SECRETS_EXTENSION_IMAGE=drone/kubernetes-secrets:latest

#export DOMAIN=drone.k3s.example.com
#export REGISTRY_DOMAIN=registry.k3s.example.com
export PVC_SIZE=10Gi
export DRONE_GIT_ALWAYS_AUTH=true
#export DRONE_GITEA_SERVER=https://gitea.k3s.example.com
#export DRONE_SERVER_HOST=drone.k3s.example.com


## Generate secrets:
if [[ ! -f ${SECRET}.sealed_secret.yaml ]]; then
    export DRONE_RPC_SECRET=$(gen_password)
    check_length 50 DRONE_RPC_SECRET
    echo "OK: Generated DRONE_RPC_SECRET: ${DRONE_RPC_SECRET}"

    export DRONE_KUBERNETES_SECRET_KEY=$(gen_password)
    check_length 50 DRONE_KUBERNETES_SECRET_KEY

    #generate ssh key
    SSH_TMP=$(mktemp -u)
    ssh-keygen -b 3072 -t rsa -f ${SSH_TMP} -q -N "" -C digitalocean-drone-runner
    export SSH_PRIVATE_KEY=$(cat ${SSH_TMP})
    export SSH_PUBLIC_KEY=$(cat ${SSH_TMP}.pub)
    rm ${SSH_TMP} ${SSH_TMP}.pub
else
    ## Set placeholder values for variables we don't need this run:
    export SSH_PRIVATE_KEY=placeholder
    export SSH_PUBLIC_KEY=placeholder
fi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/drone/drone.namespace.template.yaml
    $TEMPLATE_SRC/drone/drone.serviceaccount.template.yaml
    $TEMPLATE_SRC/drone/drone.rbac.template.yaml
    $TEMPLATE_SRC/drone/drone.pvc.template.yaml
    $TEMPLATE_SRC/drone/drone.ingress.template.yaml
    $TEMPLATE_SRC/drone/drone.template.yaml
    $TEMPLATE_SRC/drone/drone.runner.template.yaml
    $TEMPLATE_SRC/drone/drone.digitalocean_runner.template.yaml
    $TEMPLATE_SRC/drone/drone.secrets_plugin.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=(
    $TEMPLATE_SRC/drone/id_rsa.template.yaml
    $TEMPLATE_SRC/drone/id_rsa.pub.template.yaml
    $TEMPLATE_SRC/drone/docker.config.template.yaml
)
