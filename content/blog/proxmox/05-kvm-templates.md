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
DISTRO=arch TEMPLATE_ID=9000 ./proxmox_kvm.sh template
```

### Debian (bullseye)

```bash
DISTRO=debian TEMPLATE_ID=9001 ./proxmox_kvm.sh template
```

### Ubuntu (20.04 LTS)

```bash
DISTRO=ubuntu TEMPLATE_ID=9002 ./proxmox_kvm.sh template
```

### Fedora (35)

```bash
DISTRO=fedora TEMPLATE_ID=9003 ./proxmox_kvm.sh template
```

### Docker

You can install Docker on any of the supported distributions. Pass the
`INSTALL_DOCKER=yes` variable to attach a small install script to the
VM so that it automatically installs Docker on first boot, via
cloud-init:

```bash
VM_HOSTNAME=docker \
DISTRO=debian \
TEMPLATE_ID=9998 \
INSTALL_DOCKER=yes \
./proxmox_kvm.sh template
```

### FreeBSD (13)

FreeBSD does not allow root login, so you must choose an alternate `VM_USER`:

```bash
DISTRO=freebsd TEMPLATE_ID=9004 VM_USER=fred ./proxmox_kvm.sh template
```

### Any other cloud image

You can use any other generic cloud image directly by setting
`IMAGE_URL`. For example, this script knows nothing about OpenBSD, but
you can find a third party cloud image from [this
website](https://bsd-cloud-image.org/), and so you can use their image
with this script:

```bash
DISTRO=OpenBSD \
TEMPLATE_ID=9999 \
VM_USER=fred \
IMAGE_URL=https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/openbsd/7.0/2021-12-11/openbsd-7.0.qcow2 \
./proxmox_kvm.sh template
```

## Creating new virtual machines by cloning these templates

This script uses a custom cloud-init User Data section, which means
you cannot use the Proxmox GUI to edit cloud-init data. Therefore, the
script encapsulates this logic for you, and makes it easy to clone the
template:

```bash
TEMPLATE_ID=9000 \
VM_ID=100 \
VM_HOSTNAME=my_arch \
./proxmox_kvm.sh clone
```

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_kvm.sh)

{{< code file="/src/proxmox/proxmox_kvm.sh" language="shell" >}}
