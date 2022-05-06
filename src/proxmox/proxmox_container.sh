#!/bin/bash
## Automated script to setup LXC containers on Proxmox (PVE)

## Choose your distribution base template:
## Supported: arch, debian, alpine
DISTRO=${DISTRO:-arch}

## Set these variables to configure the container:
## (All variables can be overriden from the parent environment)
CONTAINER_ID=${CONTAINER_ID:-8001}
CONTAINER_HOSTNAME=${CONTAINER_HOSTNAME:-$(echo ${DISTRO} | cut -d- -f1)}
# Container CPUs:
NUM_CORES=${NUM_CORES:-1}
# Container RAM in MB:
MEMORY=${MEMORY:-2048}
# Container swap size in MB:
SWAP_SIZE=${SWAP_SIZE:-${MEMORY}}
# Container root filesystem size in GB:
FILESYSTEM_SIZE=${FILESYSTEM_SIZE:-50}
## Point to the local authorized_keys file to copy into container:
SSH_KEYS=${SSH_KEYS:-${HOME}/.ssh/authorized_keys}
## To install docker inside the container, set INSTALL_DOCKER=yes
INSTALL_DOCKER=${INSTALL_DOCKER:-no}

## Arch Linux specific:
ARCH_MIRROR=${ARCH_MIRROR:-"https://mirror.rackspace.com"}

## Proxmox specific variables:
PUBLIC_BRIDGE=${PUBLIC_BRIDGE:-vmbr0}
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-local}
CONTAINER_STORAGE=${CONTAINER_STORAGE:-local-lvm}

## Set YES=yes to disable all confirmations:
YES=${YES:-no}

## You can provide a password, or leave it blank to generate a secure one:
PASSWORD=${PASSWORD}
if [[ ${#PASSWORD} == 0 ]]; then
    if ! command -v openssl &> /dev/null; then
        echo "openssl is not installed. Cannot generate random password."
        exit 1
    fi
    ## Generate a long random password with openssl:
    PASSWORD=$(openssl rand -hex 45)
fi

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
    ## De-Reference common short distro aliases to the longer name:
    if [[ ${DISTRO} == "arch" ]] || [[ ${DISTRO} == "archlinux" ]]; then
        DISTRO="archlinux-base"
    elif [[ ${DISTRO} == "debian" ]] || [[ ${DISTRO} == "debian-11" ]]; then
        DISTRO="debian-11-standard"
    elif [[ ${DISTRO} == "alpine" ]] || [[ ${DISTRO} == "alpine-3" ]]; then
        DISTRO="alpine-3.15"
    fi
    ## Only support specific templates that have been tested to work:
    if [[ ${DISTRO} == "archlinux-base" ]]; then
        echo "Creating Arch Linux container"
    elif [[ ${DISTRO} == "debian-11-standard" ]]; then
        echo "Creating Debian 11 container"
    elif [[ ${DISTRO} == "alpine-3.15" ]]; then
        echo "Creating Alpine 3.15 container"
    else
        echo "DISTRO '${DISTRO}' is not supported by this script yet."
        exit 1
    fi

    test -f ${SSH_KEYS} || \
        (echo "Missing required SSH authorized_keys file: ${SSH_KEYS}" && exit 1)

    ## Download latest template
    echo "Updating templates ... "
    pveam update
    TEMPLATE=$(pveam available --section system | grep ${DISTRO} | sort -n | \
                       head -1 | tr -s ' ' | cut -d" " -f2)
    pveam download ${TEMPLATE_STORAGE} ${TEMPLATE}

    read -r -d '' CREATE_COMMAND <<EOM || true
    pct create ${CONTAINER_ID}
    ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}
    --storage ${CONTAINER_STORAGE}
    --rootfs ${CONTAINER_STORAGE}:${FILESYSTEM_SIZE}
    --unprivileged 1
    --cores ${NUM_CORES}
    --features nesting=1,keyctl=1,fuse=1
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
    set +x

    if [[ "${DISTRO}" =~ ^arch ]]; then
        _archlinux_init
    elif [[ "${DISTRO}" =~ ^debian ]]; then
        _debian_init
    elif [[ "${DISTRO}" =~ ^alpine ]]; then
        _alpine_init
    fi

    set +x
    echo
    echo "Container IP address (eth0):"
    pct exec ${CONTAINER_ID} -- sh -c "ip addr show dev eth0 | grep inet"
}

_debian_init() {
    # Mask these services because they fail:
    pct exec ${CONTAINER_ID} -- systemctl mask systemd-journald-audit.socket
    pct exec ${CONTAINER_ID} -- systemctl mask sys-kernel-config.mount
    pct exec ${CONTAINER_ID} -- env apt-get update
    pct exec ${CONTAINER_ID} -- env DEBIAN_FRONTEND=noninteractive \
        apt-get \
        -o Dpkg::Options::="--force-confnew" \
        -fuy \
        dist-upgrade

    _ssh_config
    pct exec ${CONTAINER_ID} -- systemctl enable --now ssh

    if [[ ${INSTALL_DOCKER} == "yes" ]]; then
        pct exec ${CONTAINER_ID} -- apt-get -y install \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        pct exec ${CONTAINER_ID} -- sh -c "curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
        pct exec ${CONTAINER_ID} -- sh -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
        pct exec ${CONTAINER_ID} -- apt-get update
        pct exec ${CONTAINER_ID} -- apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
}

_archlinux_init() {
    pct exec ${CONTAINER_ID} -- pacman-key --init
    pct exec ${CONTAINER_ID} -- pacman-key --populate
    pct exec ${CONTAINER_ID} -- /bin/sh -c "echo 'Server = ${ARCH_MIRROR}/archlinux/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist"
    pct exec ${CONTAINER_ID} -- pacman -Syu --noconfirm

    # Mask this service because its failing:
    pct exec ${CONTAINER_ID} -- systemctl mask systemd-journald-audit.socket

    _ssh_config
    pct exec ${CONTAINER_ID} -- systemctl enable --now sshd

    if [[ ${INSTALL_DOCKER} == "yes" ]]; then
        pct exec ${CONTAINER_ID} -- pacman -S --noconfirm docker
        pct exec ${CONTAINER_ID} -- systemctl enable --now docker
    fi

}

_alpine_init() {
    pct exec ${CONTAINER_ID} -- apk upgrade -U
    pct exec ${CONTAINER_ID} -- apk add openssh
    _ssh_config
    pct exec ${CONTAINER_ID} -- rc-update add sshd
    pct exec ${CONTAINER_ID} -- /etc/init.d/sshd start

    if [[ ${INSTALL_DOCKER} == "yes" ]]; then
        pct exec ${CONTAINER_ID} -- apk add docker
        pct exec ${CONTAINER_ID} -- rc-update add docker
        pct exec ${CONTAINER_ID} -- /etc/init.d/docker start
    fi
}

_ssh_config() {
    SSHD_CONFIG=$(mktemp)
    cat <<EOM > ${SSHD_CONFIG}
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOM
    pct push ${CONTAINER_ID} ${SSHD_CONFIG} /etc/ssh/sshd_config
}

destroy() {
    _confirm yes "This will destroy container ${CONTAINER_ID} ($(pct config ${CONTAINER_ID} | grep hostname))"
    set -x
    pct stop "${CONTAINER_ID}" || true
    pct destroy "${CONTAINER_ID}"
}

login() {
    pct enter ${CONTAINER_ID}
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
