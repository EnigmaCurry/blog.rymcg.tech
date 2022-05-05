---
title: "Proxmox part 4: Arch Linux container"
date: 2022-05-04T00:02:00-06:00
tags: ['proxmox']
---

Here is an automated script to install a fully updated Arch Linux
container (LXC) on Proxmox.

## LXC?

According to the [LXC Introduction
page](https://linuxcontainers.org/lxc/introduction/)

```
LXC is a userspace interface for the Linux kernel containment
features. Through a powerful API and simple tools, it lets Linux
users easily create and manage system or application containers.
```

So LXC is another way to create containers on Linux, and it predates
both Docker and Podman. Unlike Docker containers, LXC containers are
more stateful: inside of an LXC container you usually run systemd,
use the package manager to install software, and basically treat the
system like a virtual machine (more like a "pet", less like "cattle").

Unlike a VM though (eg. VMWare, VirtualBox, KVM), LXC containers don't
have any virtualized hardware: they run dirctly on the host system,
under the same Linux kernel. You also can't use a normal Linux
distribution `.iso` file to install an LXC container, because LXC
can't "boot" a second kernel.

[In Proxmox, you install LXC containers via maintained
templates.](https://pve.proxmox.com/wiki/Linux_Container) The script
outlined in this post is simply automation for the process of
downloading the template and creating a container based upon it. At
the end of this you'll have a fully updated Arch Linux LXC container
up and running, with secured SSH pubkey-only authentication.

## Usage

Login to your Proxmox server as the root user via SSH.

Download the script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/archlinux_container.sh
```

Edit the variables at the top of the script, or create them in your
shell environment to override them.

Make the script executable:

```bash
chmod a+x archlinux_container.sh
```

And run it:

```bash
./archlinux_container.sh create
```

The container will be created, and at the very end the IP address of
the new container will be printed. You can login via SSH to the `root`
user.

Password authentication is disabled; you must use SSH public key
authentication. The default configuration will use the same SSH keys
as you used for the root Proxmox user (`/root/.ssh/authorized_keys`).

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/archlinux_container.sh)

{{< code file="/src/proxmox/archlinux_container.sh" language="shell" >}}

