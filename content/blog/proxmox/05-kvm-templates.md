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

## Warnings for alternative proxmox storage backends (NFS)

This script is setup by default for the `local-lvm` storage pool. If
that's what you want, skip reading this section. You can also use
`local-zfs`, by setting `STORAGE=local-zfs`. NFS storage can be used,
with caveats. Other filesystems like ceph or gluster have not been
tested. Finally, the Proxmox OS drive (`local`) should never be used
for storing VMs. If you want to use anything other than `local-lvm`,
you must change the `STORAGE` variable, as shown in all examples.

You can store KVM templates on any storage pool that is tagged for the
`Disk Image` content type (by default, only `local-lvm` is set this
way). If you have added an NFS storage backend (and tagged it for the
`Disk Image` content type), you may encounter this error when creating
the final VM template (with `qm template {TEMPLATE_ID}`):


```
## Error you may see if using NFS or another alternative storage backend:
/usr/bin/chattr: Operation not supported while reading flags on /mnt/pve/{STORAGE}/images/{TEMPLATE_ID}/base-{TEMPLATE_ID}-disk-0.raw
```

This is because NFS does not support immutable files, but this is not
especially important as long as Proxmox is the only client of this
storage pool. So, this error may be ignored.

The examples below assume that you are using `STORAGE=local-lvm`, but
you may change this to any other compatible storage pool name.

If you do change the default `STORAGE`, please note that the `DISK`
parameter might need slight tweaking as well, as shown in the script:

```
## Depending on the storage backend, the DISK path may differ slightly:
if [ "${STORAGE_TYPE}" == 'nfs' ]; then
    # nfs path:
    DISK="${STORAGE}:${TEMPLATE_ID}/vm-${TEMPLATE_ID}-disk-0.raw"
elif [ "${STORAGE_TYPE}" == 'local' ]; then
    # lvm path:
    DISK="${STORAGE}:vm-${TEMPLATE_ID}-disk-0"
else
    echo "only 'local' (lvm) or 'nfs' storage backends are supported at this time"
    exit 1
fi
```

Be sure to set `STORAGE_TYPE` to `local` if you're using the local-lvm backend
or to `nfs`  if you're using the NFS backend. If you're using any other
storage backend, you may need to tweak the `DISK` parameter and alter this
`if` statement accordingly. I don't know why the naming is different between
storage backends (if you do, [please file an issue](https://github.com/EnigmaCurry/blog.rymcg.tech/issues)),
but what I do know is that it's very annoying. I don't have a good solution
here other than to hardcode the path differences into an if statement and
to document the issue here.

## Creating KVM templates

You can create templates for every Operating System you wish to run.
In order to follow along with this blog series, you should create all
of the following templates with the same `TEMPLATE_ID` shown, as these
templates will be used in subsequent posts (you'll need at least the
ones for Arch Linux (`9000`), Debian (`9001`), and Docker (`9998`)).

### Arch Linux

```bash
DISTRO=arch TEMPLATE_ID=9000 STORAGE_TYPE=local STORAGE=local-lvm ./proxmox_kvm.sh template
```

### Debian (13; trixie)

```bash
DISTRO=debian TEMPLATE_ID=9001 STORAGE_TYPE=local STORAGE=local-lvm ./proxmox_kvm.sh template
```

### Ubuntu (noble; 24.04 LTS)

```bash
DISTRO=ubuntu TEMPLATE_ID=9002 STORAGE_TYPE=local STORAGE=local-lvm ./proxmox_kvm.sh template
```

### Fedora (43)

```bash
DISTRO=fedora TEMPLATE_ID=9003 STORAGE_TYPE=local STORAGE=local-lvm ./proxmox_kvm.sh template
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
STORAGE_TYPE=local \
STORAGE=local-lvm \
./proxmox_kvm.sh template
```

### FreeBSD (15)

FreeBSD does not allow root login, so you must choose an alternate `VM_USER`:

```bash
DISTRO=freebsd TEMPLATE_ID=9004 STORAGE=local-lvm VM_USER=fred ./proxmox_kvm.sh template
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
STORAGE=local-lvm \
IMAGE_URL=https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/openbsd/7.0/2021-12-11/openbsd-7.0.qcow2 \
./proxmox_kvm.sh template
```

## Creating new virtual machines by cloning these templates

This script uses a custom cloud-init User Data template that is copied
to `/var/lib/vz/snippets/vm-${VM_ID}-user-data.yml` which means that
you cannot use the Proxmox GUI to edit cloud-init data. Therefore,
this script encapsulates this logic for you, and makes it easy to
clone the template:

```bash
TEMPLATE_ID=9000 \
VM_ID=100 \
VM_HOSTNAME=my_arch \
./proxmox_kvm.sh clone
```

Start the VM whenever you're ready:

```bash
qm start 100
```

cloud-init will run the first time the VM boots. This will install the
Qemu guest agent, which may take a few minutes.

Wait a bit for the boot to finish, then find out what the IP address
is:

```bash
VM_ID=100 ./proxmox_kvm.sh get_ip
```


## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_kvm.sh)

{{< code file="/src/proxmox/proxmox_kvm.sh" language="shell" >}}
