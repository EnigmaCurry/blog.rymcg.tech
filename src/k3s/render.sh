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
    if [[ `which xargs 2> /dev/null` == "" ]]; then
        echo "Missing xargs: install findutils"
        echo "(Debian/Ubuntu): apt install findutils"
        return 1
    fi
}

check_env() {
    export TEMPLATE_VARS=""
    for v in "${ENV_VARS[@]}"; do
        TEMPLATE_VARS=$TEMPLATE_VARS"\$$v"
    done
}

render() {
    for f in "${TEMPLATES[@]}"; do
        if [[ $f == *.template.yaml ]]; then
            file=$(echo $f | awk -F'/' '{print $NF}' | sed 's/\.template\.yaml/\.yaml/')
            if [[ -f $file ]]; then
                echo "$file already exists! Delete it first if you wish to recreate it."
            else
                echo "downloading: $f"
                curl -sSL "$f" | envsubst $TEMPLATE_VARS > $file
                echo "Rendered $file"
            fi
        fi
    done
}

main() {
    set -e
    source env.sh
    check_env
    render
}

main
