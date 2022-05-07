---
title: "Proxmox part 5: KVM and Cloud-Init"
date: 2022-05-06T00:02:00-06:00
tags: ['proxmox']
---

This post introduces a shell script to create KVM virtual machine
templates on Proxmox.

## KVM?

According to Wikipedia:

```
Kernel-based Virtual Machine (KVM) is a virtualization module in the
Linux kernel that allows the kernel to function as a hypervisor.
```

With KVM you can create virtual machines that are hardware
accelerated. Unlike a container, a virtual machine boots its own
virtual hardware (CPU, memory, disk, etc). Each KVM virtual machine is
running its own (Linux) kernel and is isolated from the host operating
system.

The main advantages of a virtual machine are greater isolation and the
ability to run any operating system. (Whereas a container is limited
to running under the exact same Linux kernel as the host.)

Proxmox supports both KVM virtual machines and LXC containers.
[Containers were covered in part 4](./04-containers). This post will
cover building KVM templates. 

## Cloud-Init?

Another advantage of KVM is the ability to use cloud images (using
[cloud-init](https://pve.proxmox.com/wiki/Cloud-Init_Support)) to be
able to customize the username and SSH keys, and custom scripts for
installing additional software. Cloud-Init will handle all of the
configuration on the first boot of the VM.

## Install the script

Login to your Proxmox server as the root user via SSH.

Download the script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_kvm.sh
```

Read all of the comments, and then edit the variables at the top of
the script to change any defaults you desire. You can also override
the configuration defaults in your parent shell environment as will be
shown.

Make the script executable:

```bash
chmod a+x proxmox_kvm.sh
```

## Creating KVM templates

You can create templates for every Operating System you wish to run:

### Arch Linux

```bash
DISTRO=arch VM_ID=9000 ./proxmox_kvm.sh template
```

### Debian (bullseye)

```bash
DISTRO=debian VM_ID=9001 ./proxmox_kvm.sh template
```

### Ubuntu (20.04 LTS)

```bash
DISTRO=ubuntu VM_ID=9002 ./proxmox_kvm.sh template
```

### Fedora (35)

```bash
DISTRO=fedora VM_ID=9003 ./proxmox_kvm.sh template
```

### FreeBSD (13)

FreeBSD does not allow root login, so you must choose an alternate `VM_USER`:

```bash
DISTRO=freebsd VM_ID=9004 VM_USER=fred ./proxmox_kvm.sh template
```

### Any other cloud image

You can use any other generic cloud image directly by setting
`IMAGE_URL`. For example, this script knows nothing about OpenBSD, but
you can find a third party cloud image from [this
website](https://bsd-cloud-image.org/), and so you can use their image
with this script:

```bash
DISTRO=OpenBSD \
VM_ID=9999 \
VM_USER=fred \
IMAGE_URL=https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/openbsd/7.0/2021-12-11/openbsd-7.0.qcow2 \
./proxmox_kvm.sh template
```

## Creating new virtual machines from these templates

In the Proxmox GUI you can easily clone a new VM from a template. 

 * Find the template ID in the node list, right click it, and select
`Clone`. 
 * Choose a new VM ID and new name.
 * Click `Clone`.
 * Find the new cloned VM in the node list, and then click on `Cloud-Init`
 * Change the username you want.
 * Click on the `Snapshots` tab and click `Take Snapshot` (optional).
   This will allow you to rollback to a clean state (before first
   boot) if you need to later on.
 * Click the `Start` button to start the VM.
 * Click on the `Hardware` tab and find the Network Device `net0` and
   it shows the MAC address eg. `virtio=[MAC ADDRESS]`
 * Look on your LAN router and find the DHCP lease for the VM MAC
   address.
 * SSH into the new VM using the IP address your DHCP server handed
   out, using the username you set in Cloud-Init.

You can automate all of the above steps using the root Proxmox
console:

```bash
TEMPLATE_ID=9999
VM_ID=123

qm clone ${TEMPLATE_ID} ${VM_ID} --name my-pet
qm set ${VM_ID} --ciuser ryan
qm snapshot ${VM_ID} init
qm start ${VM_ID}
```
