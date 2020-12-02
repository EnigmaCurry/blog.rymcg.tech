gen_password() { head -c 16 /dev/urandom | sha256sum | cut -d " " -f 1; }

## kube_run IMAGE CMD_ARGS
kube_run() {
    IMAGE=${1}
    CMD_ARGS=${@:2}
    eval "kubectl run --quiet -i --rm --tty kube-run-${IMAGE}-${RANDOM} --image=${IMAGE} --restart=Never -- ${CMD_ARGS}"
}

## check_length MIN_LENGTH VAR_NAME
check_length() {
    MIN_LENGTH=${1}
    VAR_NAME=${2}
    if [[ $(echo ${!VAR_NAME} | wc -c) -lt ${MIN_LENGTH} ]]; then
        echo "ERROR: ${VAR_NAME} length less than ${MIN_LENGTH} characters: ${!VAR_NAME}"
        exit 1
    fi
}

## htpasswd USER PASSWORD
htpasswd() {
    kube_run alpine /bin/sh -c \""apk add --no-cache apache2-utils &> /dev/null && htpasswd -Bbn ${1} ${2} | head -n 1 2> /dev/null\""
}
