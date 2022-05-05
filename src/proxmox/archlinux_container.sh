#!/bin/bash
## Interactive script to setup fully updated Arch Linux container on Proxmox (PVE)

## Configure these variables to configure the container:
CONTAINER_ID=${CONTAINER_ID:-8001}
CONTAINER_HOSTNAME=${CONTAINER_HOSTNAME:-arch}
NUM_CORES=${NUM_CORES:-1}
MEMORY=${MEMORY:-2048}
SWAP_SIZE=${SWAP_SIZE:-${MEMORY}}
SSH_KEYS=${SSH_KEYS:-${HOME}/.ssh/authorized_keys}
PASSWORD=${PASSWORD:-$(openssl rand -hex 45)}
ARCH_MIRROR="https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"

## Configure these variables to configure the PVE host:
PUBLIC_BRIDGE=vmbr0
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-local}
CONTAINER_STORAGE=${CONTAINER_STORAGE:-local-lvm}

## Set YES=yes to disable all confirmations:
YES=${YES:-no}

_confirm() {
    test ${YES:-no} == "yes" && return 0
    default=$1; prompt=$2; question=${3:-". Proceed?"}
    if [[ $default == "y" || $default == "yes" ]]; then
        dflt="Y/n"
    else
        dflt="y/N"
    fi
    read -p "${prompt}${question} (${dflt}): " answer
    answer=${answer:-${default}}
    if [[ ${answer,,} == "y" || ${answer,,} == "yes" ]]; then
        return 0
    else
        echo "Exiting."
        [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
}

create() {
    set -e
    test -f ${SSH_KEYS} || \
        (echo "Missing required SSH authorized_keys file: ${SSH_KEYS}" && exit 1)

    ## Download latest template
    echo "Updating templates ... "
    pveam update
    TEMPLATE=$(pveam available | grep archlinux-base | sort -n | \
                   head -1 | tr -s ' ' | cut -d" " -f2)
    pveam download ${TEMPLATE_STORAGE} ${TEMPLATE}

    read -r -d '' CREATE_COMMAND <<EOM || true
    pct create ${CONTAINER_ID}
    ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}
    --storage ${CONTAINER_STORAGE}
    --unprivileged 1
    --cores ${NUM_CORES}
    --features nesting=1
    --hostname ${CONTAINER_HOSTNAME}
    --memory ${MEMORY}
    --password ${PASSWORD}
    --net0 name=eth0,bridge=${PUBLIC_BRIDGE},firewall=1,ip=dhcp
    --swap ${SWAP_SIZE}
    --ssh-public-keys ${SSH_KEYS}
EOM

    echo ""
    echo "${CREATE_COMMAND}"
    echo ""
    _confirm yes "^^ This will create the container using the above settings"
    set -x
    ${CREATE_COMMAND}

    pct start ${CONTAINER_ID}
    sleep 5
    pct exec ${CONTAINER_ID} -- pacman-key --init
    pct exec ${CONTAINER_ID} -- pacman-key --populate
    pct exec ${CONTAINER_ID} -- /bin/sh -c "echo 'Server = ${ARCH_MIRROR}' > /etc/pacman.d/mirrorlist"
    pct exec ${CONTAINER_ID} -- pacman -Syu --noconfirm

    SSHD_CONFIG=$(mktemp)
    cat <<EOM > ${SSHD_CONFIG}
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
EOM
    pct push ${CONTAINER_ID} ${SSHD_CONFIG} /etc/ssh/sshd_config
    pct exec ${CONTAINER_ID} -- systemctl enable --now sshd

    # Mask this service because its failing:
    pct exec ${CONTAINER_ID} -- systemctl mask systemd-journald-audit.socket

    set +x
    echo
    echo "Container IP address (eth0):"
    pct exec ${CONTAINER_ID} -- sh -c "ip addr show dev eth0 | grep inet"
}

destroy() {
    _confirm yes "This will destroy container ${CONTAINER_ID}"
    set -x
    pct stop "${CONTAINER_ID}" || true
    pct destroy "${CONTAINER_ID}"
}

if [[ $# == 0 ]]; then
    echo "Commands:"
    echo " create"
    echo " destroy"
    exit 1
elif [[ $# > 1 ]]; then
    shift
    echo "Invalid arguments: $@"
    exit 1
else
    "$@"
fi
