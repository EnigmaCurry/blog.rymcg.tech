#!/bin/bash

## Create a Virtual Private Cloud (VPC) on Proxmox
## See https://blog.rymcg.tech/blog/proxmox/09-vpc/

## VPC Bridge configuration:
VPC_BRIDGE=${VPC_BRIDGE:-vmbr99}
VPC_HOST_CIDR=${VPC_HOST_CIDR:-10.99.0.2/24}

## Router VM configuration:
ROUTER_VM_ID=${ROUTER_VM_ID:-200}
ROUTER_HOSTNAME=${ROUTER_HOSTNAME:-router}
ROUTER_DISK_SIZE=${ROUTER_DISK_SIZE:-32G}
ROUTER_MEMORY=${ROUTER_MEMORY:-2048}
ROUTER_CORES=${ROUTER_CORES:-1}
PUBLIC_BRIDGE=${PUBLIC_BRIDGE:-vmbr0}

## Client VM configuration:
CLIENT_VM_ID=${CLIENT_VM_ID:-201}
CLIENT_HOSTNAME=${CLIENT_HOSTNAME:-client}
CLIENT_DISK_SIZE=${CLIENT_DISK_SIZE:-32G}
CLIENT_MEMORY=${CLIENT_MEMORY:-2048}
CLIENT_CORES=${CLIENT_CORES:-1}

## Shared configuration:
STORAGE=${STORAGE:-local-lvm}

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
        echo "Canceled."
        return 1
    fi
}

create_vpc() {
    set -e
    echo "Creating VPC bridge ${VPC_BRIDGE} ..."

    ## Check if bridge already exists:
    if pvesh get /nodes/${HOSTNAME}/network/${VPC_BRIDGE} >/dev/null 2>&1; then
        echo "Bridge ${VPC_BRIDGE} already exists."
        return 0
    fi

    pvesh create /nodes/${HOSTNAME}/network \
      --iface ${VPC_BRIDGE} \
      --type bridge \
      --cidr ${VPC_HOST_CIDR} \
      --autostart 1 \
      --comments "VPC private bridge - no NAT"

    pvesh set /nodes/${HOSTNAME}/network

    echo
    echo "Created VPC bridge: ${VPC_BRIDGE}"
    echo "  Host management IP: ${VPC_HOST_CIDR}"
    echo "  No masquerade, no ip_forward — routing is handled by the router VM."
}

create_router() {
    set -e
    echo "Creating router VM ${ROUTER_VM_ID} (${ROUTER_HOSTNAME}) ..."

    qm create ${ROUTER_VM_ID} \
       --name "${ROUTER_HOSTNAME}" \
       --sockets ${ROUTER_CORES} \
       --memory ${ROUTER_MEMORY} \
       --net0 "virtio,bridge=${PUBLIC_BRIDGE}" \
       --net1 "virtio,bridge=${VPC_BRIDGE}" \
       --scsihw virtio-scsi-pci \
       --serial0 socket \
       --vga serial0 \
       --onboot 1

    ## Allocate a blank disk:
    pvesh create /nodes/${HOSTNAME}/storage/${STORAGE}/content \
      --vmid ${ROUTER_VM_ID} \
      --filename vm-${ROUTER_VM_ID}-disk-0 \
      --size ${ROUTER_DISK_SIZE} \
      --format raw
    qm set ${ROUTER_VM_ID} --scsi0 ${STORAGE}:vm-${ROUTER_VM_ID}-disk-0
    qm set ${ROUTER_VM_ID} --boot order=scsi0

    echo
    echo "Created router VM: ${ROUTER_VM_ID} (${ROUTER_HOSTNAME})"
    echo "  net0: ${PUBLIC_BRIDGE} (internet-facing)"
    echo "  net1: ${VPC_BRIDGE} (VPC private side)"
    echo "  Disk: ${ROUTER_DISK_SIZE} on ${STORAGE}"
    echo
    echo "Next steps:"
    echo "  1. Attach an OS ISO via the Proxmox GUI (Hardware > CD/DVD Drive)"
    echo "  2. Start the VM and install the OS"
    echo "  3. Configure NAT/masquerade inside the router (see blog post)"
}

create_vm() {
    set -e
    echo "Creating client VM ${CLIENT_VM_ID} (${CLIENT_HOSTNAME}) ..."

    qm create ${CLIENT_VM_ID} \
       --name "${CLIENT_HOSTNAME}" \
       --sockets ${CLIENT_CORES} \
       --memory ${CLIENT_MEMORY} \
       --net0 "virtio,bridge=${VPC_BRIDGE}" \
       --scsihw virtio-scsi-pci \
       --serial0 socket \
       --vga serial0 \
       --onboot 1

    ## Allocate a blank disk:
    pvesh create /nodes/${HOSTNAME}/storage/${STORAGE}/content \
      --vmid ${CLIENT_VM_ID} \
      --filename vm-${CLIENT_VM_ID}-disk-0 \
      --size ${CLIENT_DISK_SIZE} \
      --format raw
    qm set ${CLIENT_VM_ID} --scsi0 ${STORAGE}:vm-${CLIENT_VM_ID}-disk-0
    qm set ${CLIENT_VM_ID} --boot order=scsi0

    echo
    echo "Created client VM: ${CLIENT_VM_ID} (${CLIENT_HOSTNAME})"
    echo "  net0: ${VPC_BRIDGE} (VPC only — isolated from internet)"
    echo "  Disk: ${CLIENT_DISK_SIZE} on ${STORAGE}"
    echo
    echo "Next steps:"
    echo "  1. Attach an OS ISO via the Proxmox GUI (Hardware > CD/DVD Drive)"
    echo "  2. Start the VM and install the OS"
    echo "  3. Set the default gateway to the router's VPC IP address"
}

create_all() {
    create_vpc
    echo
    create_router
    echo
    create_vm
    echo
    echo "=== VPC setup complete ==="
    echo "Attach OS ISOs to both VMs via the Proxmox GUI, then start them."
}

status() {
    echo "=== VPC Bridge ==="
    if pvesh get /nodes/${HOSTNAME}/network/${VPC_BRIDGE} >/dev/null 2>&1; then
        pvesh get /nodes/${HOSTNAME}/network/${VPC_BRIDGE} --output-format=yaml 2>/dev/null
    else
        echo "Bridge ${VPC_BRIDGE} does not exist."
    fi
    echo
    echo "=== Router VM (${ROUTER_VM_ID}) ==="
    if qm status ${ROUTER_VM_ID} >/dev/null 2>&1; then
        qm status ${ROUTER_VM_ID}
        qm config ${ROUTER_VM_ID} | grep -E "^(name|net[0-9]|scsi[0-9]|memory|sockets):"
    else
        echo "VM ${ROUTER_VM_ID} does not exist."
    fi
    echo
    echo "=== Client VM (${CLIENT_VM_ID}) ==="
    if qm status ${CLIENT_VM_ID} >/dev/null 2>&1; then
        qm status ${CLIENT_VM_ID}
        qm config ${CLIENT_VM_ID} | grep -E "^(name|net[0-9]|scsi[0-9]|memory|sockets):"
    else
        echo "VM ${CLIENT_VM_ID} does not exist."
    fi
}

destroy() {
    echo "This will destroy the following resources:"
    echo "  - VM ${ROUTER_VM_ID} (${ROUTER_HOSTNAME})"
    echo "  - VM ${CLIENT_VM_ID} (${CLIENT_HOSTNAME})"
    echo "  - Bridge ${VPC_BRIDGE}"
    echo
    _confirm no "Are you sure you want to destroy the VPC" "?" || return 1

    echo "Destroying VPC ..."

    for VM_ID in ${ROUTER_VM_ID} ${CLIENT_VM_ID}; do
        if qm status ${VM_ID} >/dev/null 2>&1; then
            qm stop ${VM_ID} 2>/dev/null || true
            qm destroy ${VM_ID} --purge
            echo "Destroyed VM ${VM_ID}"
        else
            echo "VM ${VM_ID} does not exist, skipping."
        fi
    done

    if pvesh get /nodes/${HOSTNAME}/network/${VPC_BRIDGE} >/dev/null 2>&1; then
        pvesh delete /nodes/${HOSTNAME}/network/${VPC_BRIDGE}
        pvesh set /nodes/${HOSTNAME}/network
        echo "Destroyed bridge ${VPC_BRIDGE}"
    else
        echo "Bridge ${VPC_BRIDGE} does not exist, skipping."
    fi

    echo
    echo "VPC destroyed."
}

if [[ $# == 0 ]]; then
    echo "# Documentation: https://blog.rymcg.tech/blog/proxmox/09-vpc/"
    echo
    echo "Usage: $0 <command>"
    echo
    echo "Commands:"
    echo "  create_vpc     Create the VPC private bridge"
    echo "  create_router  Create the router VM (two NICs)"
    echo "  create_vm      Create a client VM (VPC only)"
    echo "  create_all     Create VPC bridge + router + client"
    echo "  status         Show VPC status"
    echo "  destroy        Tear down VPC, router, and client"
    echo
    echo "Environment variables (current values):"
    echo "  VPC_BRIDGE=${VPC_BRIDGE}  VPC_HOST_CIDR=${VPC_HOST_CIDR}"
    echo "  PUBLIC_BRIDGE=${PUBLIC_BRIDGE}"
    echo "  ROUTER_VM_ID=${ROUTER_VM_ID}  ROUTER_HOSTNAME=${ROUTER_HOSTNAME}"
    echo "  ROUTER_DISK_SIZE=${ROUTER_DISK_SIZE}  ROUTER_MEMORY=${ROUTER_MEMORY}"
    echo "  CLIENT_VM_ID=${CLIENT_VM_ID}  CLIENT_HOSTNAME=${CLIENT_HOSTNAME}"
    echo "  CLIENT_DISK_SIZE=${CLIENT_DISK_SIZE}  CLIENT_MEMORY=${CLIENT_MEMORY}"
    echo "  STORAGE=${STORAGE}"
    exit 1
elif [[ $# -gt 1 ]]; then
    shift
    echo "Invalid arguments: $@"
    exit 1
else
    "$@"
fi
