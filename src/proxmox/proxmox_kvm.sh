#!/bin/bash

## Create Proxmox KVM templates from cloud images

## Specify DISTRO and the latest image will be discovered automatically:
DISTRO=${DISTRO:-arch}
## Alternatively, specify IMAGE_URL to the full URL of the cloud image:
#IMAGE_URL=https://mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2


## Set these variables to configure the container:
## (All variables can be overriden from the parent environment)
VM_ID=${VM_ID:-9001}
VM_HOSTNAME=${VM_HOSTNAME:-$(echo ${DISTRO} | cut -d- -f1)}
VM_USER=${VM_USER:-root}
## Point to the local authorized_keys file to copy into VM:
SSH_KEYS=${SSH_KEYS:-${HOME}/.ssh/authorized_keys}
# Container CPUs:
NUM_CORES=${NUM_CORES:-1}
# Container RAM in MB:
MEMORY=${MEMORY:-2048}
# Container swap size in MB:
SWAP_SIZE=${SWAP_SIZE:-${MEMORY}}
# Container root filesystem size in GB:
FILESYSTEM_SIZE=${FILESYSTEM_SIZE:-50}
INSTALL_DOCKER=${INSTALL_DOCKER:-no}

PUBLIC_BRIDGE=${PUBLIC_BRIDGE:-vmbr0}

_confirm() {
    set +x
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

template() {
    set -e
    (set -x; qm create ${VM_ID})
    if [[ -v IMAGE_URL ]]; then
        _template_from_url ${IMAGE_URL}
    else
        if [[ ${DISTRO} == "arch" ]] || [[ ${DISTRO} == "archlinux" ]]; then
            _template_from_url https://mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
        elif [[ ${DISTRO} == "debian" ]] || [[ ${DISTRO} == "bullseye" ]]; then
            _template_from_url https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2
        elif [[ ${DISTRO} == "ubuntu" ]] || [[ ${DISTRO} == "focal" ]]; then
            _template_from_url https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
        elif [[ ${DISTRO} == "fedora" ]] || [[ ${DISTRO} == "fedora-35" ]]; then
            _template_from_url https://download.fedoraproject.org/pub/fedora/linux/releases/35/Cloud/x86_64/images/Fedora-Cloud-Base-35-1.2.x86_64.qcow2
        elif [[ ${DISTRO} == "freebsd" ]] || [[ ${DISTRO} == "freebsd-13" ]]; then
            if [[ ${VM_USER} == "root" ]]; then
                echo "For FreeBSD, VM_USER cannot be root. Use another username."
                qm destroy ${VM_ID}
                exit 1
            fi
            # There's a lot more images to try here:  https://bsd-cloud-image.org/
            _template_from_url https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/freebsd/13.0/freebsd-13.0-zfs.qcow2
        else
            echo "DISTRO '${DISTRO}' is not supported by this script yet."
            exit 1
        fi
    fi
    (
        set -ex
        qm set "${VM_ID}" \
           --name "${VM_HOSTNAME}" \
           --sockets "${NUM_CORES}" \
           --memory "${MEMORY}" \
           --net0 "virtio,bridge=${PUBLIC_BRIDGE}" \
           --scsihw virtio-scsi-pci \
           --scsi0 "local-lvm:vm-${VM_ID}-disk-0" \
           --ide0 none,media=cdrom \
           --ide2 local-lvm:cloudinit \
           --sshkey "${SSH_KEYS}" \
           --ipconfig0 ip=dhcp \
           --boot c \
           --bootdisk scsi0 \
           --serial0 socket \
           --vga serial0 \
           --ciuser ${VM_USER}

        if [[ "${INSTALL_DOCKER}" == "yes" ]]; then
            _install_docker
        fi

        qm resize "${VM_ID}" scsi0 "+${FILESYSTEM_SIZE}G"
        qm template "${VM_ID}"
    )
    echo "To create a VM based on this template run:"
    echo " qm clone ${VM_ID} 123 --name my-${DISTRO}"
    echo " qm set 123 --ciuser bob"
    echo " qm snapshot 123 init"
    echo " qm start 123"
}

destroy() {
    _confirm yes "This will destroy VM ${VM_ID} ($(qm config ${VM_ID} | grep name))"
    set -ex
    qm destroy ${VM_ID}
}

_install_docker() {
    ## Attach the Docker install script as Cloud-Init User Data so
    ## that it is installed automatically on first boot:
    mkdir -p /var/lib/vz/snippets
    cat <<EOF > /var/lib/vz/snippets/vm-template-${VM_ID}-user-data.yaml
#cloud-config
users:
 - name: ${VM_USER}
   gecos: ${VM_USER}
   groups: docker
   ssh_authorized_keys:
$(cat ${SSH_KEYS} | grep -E "^ssh" | xargs -iXX echo "     - XX")
runcmd:
 - sh -c "curl -sSL https://get.docker.com | sh"
EOF
    qm set "${VM_ID}" --cicustom "user=local:snippets/vm-template-${VM_ID}-user-data.yaml"
}

_template_from_url() {
    set -e
    IMAGE_URL=$1
    IMAGE=${IMAGE_URL##*/}
    TMP=/tmp/kvm-images
    mkdir -p ${TMP}
    cd ${TMP}
    test -f ${IMAGE} || wget ${IMAGE_URL}
    qm importdisk ${VM_ID} ${IMAGE} local-lvm
}

if [[ $# == 0 ]]; then
    echo "Commands:"
    echo " template"
    echo " destroy"
    exit 1
elif [[ $# > 1 ]]; then
    shift
    echo "Invalid arguments: $@"
    exit 1
else
    "$@"
fi
