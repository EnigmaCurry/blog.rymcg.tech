#!/bin/bash

## Create Proxmox KVM templates from cloud images

## Specify DISTRO and the latest image will be discovered automatically:
DISTRO=${DISTRO:-arch}
## Alternatively, specify IMAGE_URL to the full URL of the cloud image:
#IMAGE_URL=https://mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2


## Set these variables to configure the container:
## (All variables can be overriden from the parent environment)
TEMPLATE_ID=${TEMPLATE_ID:-9001}
VM_ID=${VM_ID:-100}
VM_HOSTNAME=${VM_HOSTNAME:-$(echo ${DISTRO} | cut -d- -f1)}
VM_USER=${VM_USER:-root}
VM_PASSWORD=${VM_PASSWORD:-""}
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
SNIPPETS_DIR=${SNIPPETS_DIR:-/var/lib/vz/snippets}

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
    USER_DATA_RUNCMD=()
    (set -x; qm create ${TEMPLATE_ID})
    if [[ -v IMAGE_URL ]]; then
        _template_from_url ${IMAGE_URL}
    else
        if [[ ${DISTRO} == "arch" ]] || [[ ${DISTRO} == "archlinux" ]]; then
            _template_from_url https://mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
            USER_DATA_RUNCMD+=("rm -rf /etc/pacman.d/gnupg"
                               "pacman-key --init"
                               "pacman-key --populate archlinux"
                               "pacman -Syu --noconfirm"
                               "pacman -S --noconfirm qemu-guest-agent"
                               "systemctl start qemu-guest-agent"
                               "sed -i -e 's/^#\?GRUB_TERMINAL_INPUT=.*/GRUB_TERMINAL_INPUT=\"console serial\"/' -e 's/^#\?GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT=\"console serial\"/' -e 's/^#\?GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"rootflags=compress-force=zstd console=tty0 console=ttyS0,115200\"/' /etc/default/grub"
                               "sh -c \"echo 'GRUB_SERIAL_COMMAND=\\\"serial --unit=0 --speed=115200\\\"' >> /etc/default/grub\""
                               "grub-mkconfig -o /boot/grub/grub.cfg"
                              )
        elif [[ ${DISTRO} == "debian" ]] || [[ ${DISTRO} == "bullseye" ]]; then
            _template_from_url https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2
            USER_DATA_RUNCMD+=("apt-get update"
                               "apt-get install -y qemu-guest-agent"
                               "systemctl start qemu-guest-agent"
                              )
        elif [[ ${DISTRO} == "ubuntu" ]] || [[ ${DISTRO} == "focal" ]]; then
            _template_from_url https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
        elif [[ ${DISTRO} == "fedora" ]] || [[ ${DISTRO} == "fedora-35" ]]; then
            _template_from_url https://download.fedoraproject.org/pub/fedora/linux/releases/35/Cloud/x86_64/images/Fedora-Cloud-Base-35-1.2.x86_64.qcow2
        elif [[ ${DISTRO} == "freebsd" ]] || [[ ${DISTRO} == "freebsd-13" ]]; then
            if [[ ${VM_USER} == "root" ]]; then
                echo "For FreeBSD, VM_USER cannot be root. Use another username."
                qm destroy ${TEMPLATE_ID}
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
        qm set "${TEMPLATE_ID}" \
           --name "${VM_HOSTNAME}" \
           --sockets "${NUM_CORES}" \
           --memory "${MEMORY}" \
           --net0 "virtio,bridge=${PUBLIC_BRIDGE}" \
           --scsihw virtio-scsi-pci \
           --scsi0 "local-lvm:vm-${TEMPLATE_ID}-disk-0" \
           --ide0 none,media=cdrom \
           --ide2 local-lvm:cloudinit \
           --sshkey "${SSH_KEYS}" \
           --ipconfig0 ip=dhcp \
           --boot c \
           --bootdisk scsi0 \
           --serial0 socket \
           --vga serial0 \
           --agent 1

        ## Generate cloud-init User Data script:
        if [[ "${INSTALL_DOCKER}" == "yes" ]]; then
            ## Attach the Docker install script as Cloud-Init User Data so
            ## that it is installed automatically on first boot:
            USER_DATA_RUNCMD+=("sh -c 'curl -sSL https://get.docker.com | sh'")
        fi
        mkdir -p ${SNIPPETS_DIR}
        USER_DATA=${SNIPPETS_DIR}/vm-template-${TEMPLATE_ID}-user-data.yaml
        cat <<EOF > ${USER_DATA}
#cloud-config
fqdn: ${VM_HOSTNAME}
ssh_pwauth: false
users:
 - name: ${VM_USER}
   gecos: ${VM_USER}
   groups: docker
   ssh_authorized_keys:
$(cat ${SSH_KEYS} | grep -E "^ssh" | xargs -iXX echo "     - XX")
runcmd:
EOF
        for cmd in "${USER_DATA_RUNCMD[@]}"; do
            echo " - ${cmd}" >> ${USER_DATA}
        done
        qm set "${TEMPLATE_ID}" --cicustom "user=local:snippets/vm-template-${TEMPLATE_ID}-user-data.yaml"

        ## Resize filesystem and turn into a template:
        qm resize "${TEMPLATE_ID}" scsi0 "+${FILESYSTEM_SIZE}G"
        qm template "${TEMPLATE_ID}"
    )
}

clone() {
    set -e
    qm clone "${TEMPLATE_ID}" "${VM_ID}"
    USER_DATA=vm-${VM_ID}-user-data.yaml
    cp ${SNIPPETS_DIR}/vm-template-${TEMPLATE_ID}-user-data.yaml ${SNIPPETS_DIR}/${USER_DATA}
    sed -i "s/^fqdn:.*/fqdn: ${VM_HOSTNAME}/" ${SNIPPETS_DIR}/${USER_DATA}
    if [[ -v VM_PASSWORD ]]; then
        cat <<EOF >> ${SNIPPETS_DIR}/${USER_DATA}
chpasswd:
  expire: false
  list:
    - ${VM_USER}:${VM_PASSWORD}
EOF
    fi

    qm set "${VM_ID}" \
       --name "${VM_HOSTNAME}" \
       --sockets "${NUM_CORES}" \
       --memory "${MEMORY}" \
       --cicustom "user=local:snippets/${USER_DATA}"
    #qm snapshot "${VM_ID}" init
    echo "Cloned VM ${VM_ID} from template ${TEMPLATE_ID}. To start it, run:"
    echo "  qm start ${VM_ID}"
}

get_ip() {
    set -eo pipefail
    ## Get the IP address through the guest agent
    if ! command -v jq >/dev/null; then apt install -y jq; fi
    pvesh get nodes/${HOSTNAME}/qemu/${VM_ID}/agent/network-get-interfaces --output-format=json | jq -r '.result[] | select(.name | test("eth0")) | ."ip-addresses"[] | select(."ip-address-type" | test("ipv4")) | ."ip-address"'
}

_template_from_url() {
    set -e
    IMAGE_URL=$1
    IMAGE=${IMAGE_URL##*/}
    TMP=/tmp/kvm-images
    mkdir -p ${TMP}
    cd ${TMP}
    test -f ${IMAGE} || wget ${IMAGE_URL}
    qm importdisk ${TEMPLATE_ID} ${IMAGE} local-lvm
}

if [[ $# == 0 ]]; then
    echo "# Documentation: https://blog.rymcg.tech/blog/proxmox/05-kvm-templates/"
    echo "Commands:"
    echo " template"
    echo " clone"
    echo " get_ip"
    exit 1
elif [[ $# > 1 ]]; then
    shift
    echo "Invalid arguments: $@"
    exit 1
else
    "$@"
fi
