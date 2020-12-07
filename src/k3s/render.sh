#!/bin/bash

check_programs() {
    if [[ `which curl 2> /dev/null` == "" ]]; then
        echo "Missing curl: install curl package"
        echo "(Debian/Ubuntu): apt install curl"
        return 1
    fi
    if [[ `which envsubst 2> /dev/null` == "" ]]; then
        echo "Missing envsubst: install gettext package"
        echo "(Debian/Ubuntu): apt install gettext"
        return 1
    fi
    if [[ `which kubectl 2> /dev/null` == "" ]]; then
        echo "Missing kubectl: install kubectl"
        echo " https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        return 1
    fi
    if [[ -n $SECRET && `which kubeseal 2> /dev/null` == "" ]]; then
        echo "Missing kubeseal: https://github.com/bitnami-labs/sealed-secrets/releases"
        return 1
    fi
}

check_env() {
    if [ -z "$ALL_VARS" ]; then
        echo "ERROR: Missing ALL_VARS environment variable (list of variables to pass to render)"
        exit 1
    fi
    ALL_VARS+=(TEMPLATES)
    export TEMPLATE_VARS=""
    for var in "${ALL_VARS[@]}"; do
        value=${!var}
        if [[ -z "$value" ]]; then
            echo "ERROR: Missing env var: $var"
            missing=true
        fi
        TEMPLATE_VARS=$TEMPLATE_VARS"\$$var"
    done
    if [[ -n $missing ]]; then
       exit 1
    fi
}

render() {
    for f in "${TEMPLATES[@]}"; do
        if [[ $f == *.template.* ]]; then
            file=$(echo $f | awk -F'/' '{print $NF}' | sed 's/\.template//')
            if [[ -f $file ]]; then
                echo "WARNING: $file already exists! Not overwriting it."
            else
                if [[ $f == http://* ]]; then
                    echo "ERROR: Refusing to download from non-TLS/SSL URL: $f"
                    exit 1
                elif [[ $f == https://* ]]; then
                    echo "downloading: $f"
                    tmpfile=$(mktemp)
                    if curl -sfSL "$f" > $tmpfile; then
                        echo "$TEMPLATE_VARS"
                        envsubst $TEMPLATE_VARS < $tmpfile > $file
                        rm $tmpfile
                    else
                        # Failed download
                        rm $tmpfile
                        exit 1
                    fi
                elif [[ -z $f ]]; then
                    echo "ERROR: Could not find template file: $f"
                    exit 1
                else
                    envsubst $TEMPLATE_VARS < $f > $file
                fi
                grep -o '\${[^ ]*}' $file | while read -r var; do
                    echo "ERROR: Found un-rendered variable name $var in $file"
                    rm $file
                    exit 1
                done
                echo "OK: Rendered $file"
            fi
        fi
    done
}

render_secrets() {
    SEALED_SECRET=$SECRET.sealed_secret.yaml
    CREATE_SECRET_CMD="kubectl create secret generic $SECRET --namespace ${NAMESPACE:-default} --dry-run=client -o json"
    ### Add arguments for each of ALL_SECRETS
    for var in "${ALL_SECRETS[@]}"; do
        secret_value=${!var}
        CREATE_SECRET_CMD=${CREATE_SECRET_CMD}" --from-literal=$var=$secret_value"
    done
    ### Render all SECRET_TEMPLATES
    SECRET_FILES=()
    for f in "${SECRET_TEMPLATES[@]}"; do
        if [[ $f == *.template.* ]]; then
            file=$(echo $f | awk -F'/' '{print $NF}' | sed 's/\.template//')
            if [[ ! -f $file ]]; then
                echo "ERROR: secret source file is missing: $file"
                exit 1
            fi
            SECRET_FILES+=($file)
        fi
    done
    if [[ -f $SEALED_SECRET ]]; then
        echo "WARNING: $SEALED_SECRET already exists! Not overwriting it."
        for file in "${SECRET_FILES[@]}"; do
            echo "INFO: Removing $file from aborted render"
            rm $file
        done
        return
    fi
    for file in "${SECRET_FILES[@]}"; do
        CREATE_SECRET_CMD=$CREATE_SECRET_CMD" --from-file=$file=$file"
    done
    tmp=$(mktemp --suffix=secret.yaml)
    $CREATE_SECRET_CMD > $tmp
    for file in "${SECRET_FILES[@]}"; do
        echo "OK: Removing $file now rendered as sealed secret."
        rm $file
    done
    kubeseal -o yaml <$tmp > $SEALED_SECRET
    echo "OK: Rendered sealed secret: $SEALED_SECRET"
}

ask_vars() {
    for var in "${ALL_VARS[@]}"; do
        value=${!var}
        if [[ -n $value ]]; then
            echo "OK: Using variable $var from environment: $value"
        else
            read -p "INPUT: Enter value called $var: " value
        fi
        declare -g "${var}"="${value}"
        export "${var}"
        TEMPLATE_VARS=$TEMPLATE_VARS"\$$var"
    done
}

ask_secrets() {
    for var in "${ALL_SECRETS[@]}"; do
        secret_value=${!var}
        if [[ -n $secret_value ]]; then
            echo "OK: Using secret $var from environment: $secret_value"
        else
            read -p "INPUT: Enter secret called $var: " secret_value
        fi
        declare -g "${var}"="${secret_value}"
        export "${var}"
        TEMPLATE_VARS=$TEMPLATE_VARS"\$$var"
    done
}

main() {
    set -e
    RENDER_PATH=$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)
    cd $RENDER_PATH
    if (( $# != 1 )); then
        echo "ERROR: Requires one argument: Path to env.sh"
        exit 1
    elif [[ -z $1 ]]; then
        echo "ERROR $1 not found"
        exit 1
    fi
    source $1
    ask_vars
    check_env
    if [[ ! -f $SECRET.sealed_secret.yaml && -n $SECRET && -n $ALL_SECRETS ]]; then
        TEMPLATES=( ${TEMPLATES[*]} ${SECRET_TEMPLATES[*]} )
        ask_secrets
    fi
    echo "OK: Rendering templates .."
    render
    if [[ ! -f $SECRET.sealed_secret.yaml && -n $SECRET && -n $ALL_SECRETS ]]; then
        render_secrets
    elif [[ -f $SECRET.sealed_secret.yaml ]]; then
        echo "WARNING: $SECRET.sealed_secret.yaml already exists! Not overwriting it."
    fi
}

main $*
