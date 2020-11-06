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
}

check_env() {
    if [ -z "$ALL_VARS" ]; then
        echo "Missing ALL_VARS environment variable (list of variables to pass to render)"
        exit 1
    fi
    ALL_VARS+=(TEMPLATES)
    export TEMPLATE_VARS=""
    for var in "${ALL_VARS[@]}"; do
        value=${!var}
        if [[ -z "$value" ]]; then
            echo "Missing env var: $var"
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
        if [[ $f == *.template.yaml ]]; then
            file=$(echo $f | awk -F'/' '{print $NF}' | sed 's/\.template\.yaml/\.yaml/')
            if [[ -f $file ]]; then
                echo "$file already exists! Delete it first if you wish to recreate it."
            else
                if [[ $f == http://* ]]; then
                    echo "Refusing to download from non-TLS/SSL URL: $f"
                    exit 1
                elif [[ $f == https://* ]]; then
                    echo "downloading: $f"
                    tmpfile=$(mktemp)
                    if curl -sfSL "$f" > $tmpfile; then
                        envsubst $TEMPLATE_VARS < $tmpfile > $file
                        rm $tmpfile
                    else
                        # Failed download
                        rm $tmpfile
                        exit 1
                    fi
                elif [[ -z $f ]]; then
                    echo "Could not find template file: $f"
                    exit 1
                else
                    envsubst $TEMPLATE_VARS < $f > $file
                fi
                grep -o '\${[^ ]*}' $file | while read -r var; do
                    echo "ERROR: Found un-rendered variable name $var in $file"
                    rm $file
                    exit 1
                done
                echo "Rendered $file"
            fi
        fi
    done
}

main() {
    set -e
    RENDER_PATH=$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)
    cd $RENDER_PATH
    if (( $# != 1 )); then
        echo "Requires one argument: Path to env.sh"
        exit 1
    elif [[ -z $1 ]]; then
        echo "$1 not found"
    fi
    source $1
    check_env
    render
}

main $*
