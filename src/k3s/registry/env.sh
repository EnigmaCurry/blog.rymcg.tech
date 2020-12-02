### gitea environment
## ALL_VARS is the names of all of variables passed to the templates:
export ALL_VARS=(IMAGE HTPASSWD_REALM)

export IMAGE=registry:2

## All secrets are input at *render* time, and made into sealed secret(s).
export SECRET="registry"
## List of the *names* of all of the secret variables to ask for:
## Variables not defined are interactively asked for.
## Variables that are defined, are used as-is.
export ALL_SECRETS=(HTPASSWD HA_SHARED_SECRET S3_ACCESS_KEY S3_SECRET_KEY \
                    S3_REGION S3_ENDPOINT S3_BUCKET)

## Basic Auth Realm:
export HTPASSWD_REALM="Registry Realm"

## Generate passwords:
if [[ ! -f registry.sealed_secret.yaml ]]; then
    SHA=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)
    echo "Generated password (save this): ${SHA}"
    export HTPASSWD=$(kubectl run --quiet -i --rm --tty htpasswd-gen-$RANDOM --image=alpine --restart=Never -- /bin/sh -c "apk add --no-cache apache2-utils &> /dev/null && htpasswd -Bbn admin ${SHA} | head -n 1 2> /dev/null")
    if [[ $(echo $HTPASSWD | wc -c) -lt 50 ]]; then
        echo "Error generating HTPASSWD"
        exit 1
    fi

    export HA_SHARED_SECRET=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)

fi

## Default template source directory, or http path:
## TEMPLATE_SRC=${TEMPLATE_SRC:-https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/k3s}
TEMPLATE_SRC=$(pwd)

## YAML Template locations (can be file paths or https:// URLs)
export TEMPLATES=(
    $TEMPLATE_SRC/registry/registry.configmap.template.yaml
    $TEMPLATE_SRC/registry/registry.template.yaml
)
## Secret Templates
export SECRET_TEMPLATES=()
