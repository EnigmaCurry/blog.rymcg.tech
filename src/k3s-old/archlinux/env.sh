### archlinux environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(IMAGE PVC_SIZE)

## All secrets are input at *render* time, and made into sealed secret(s).
export SECRET="archlinux"
## List of the *names* of all of the secret variables to ask for:
## Variables not defined are interactively asked for.
## Variables that are defined, are used as-is.
export ALL_SECRETS=()

## Container image
## AMD-64 image:
#export IMAGE=archlinux
## ARM-64 image:
export IMAGE=agners/archlinuxarm
export PVC_SIZE=50Gi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/storageclass/storageclass.template.yaml
    $TEMPLATE_SRC/archlinux/archlinux.pvc.template.yaml
    $TEMPLATE_SRC/archlinux/archlinux.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=()
