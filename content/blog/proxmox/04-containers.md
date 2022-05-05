---
title: "Proxmox part 4: Containers"
date: 2022-05-04T00:02:00-06:00
tags: ['proxmox']
---

Here is an automated script to install Proxmox containers (LXC).

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
more stateful: inside of an LXC container you usually run systemd, you
can SSH into one, and you use the package manager inside to install
software, and basically treat the system like a virtual machine (more
like a "pet", less like "cattle").

Unlike virtual machines (eg. KVM, VMWare, VirtualBox), containers
don't have any virtualized hardware: instead they run as a process
directly on the host system, under the same Linux kernel. You also
can't use a normal Linux distribution's `.iso` file to install an LXC
container, because LXC can't "boot" a second kernel (it can only spawn
PID 1, eg. systemd). Startup time is extremely quick.

[In Proxmox, you install LXC containers via maintained
templates.](https://pve.proxmox.com/wiki/Linux_Container) The script
outlined in this post is simply automation for the process of
downloading the template and creating a container based upon it. At
the end of this you'll have a fully updated Arch Linux or Debian LXC
container up and running, with secured SSH pubkey-only authentication.

## Usage

Login to your Proxmox server as the root user via SSH.

Download the script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_container.sh
```

Edit the variables at the top of the script, or create them in your
shell environment to override them.

Make the script executable:

```bash
chmod a+x proxmox_container.sh
```

And run it:

```bash
./proxmox_container.sh create
```

The container will be created, and at the very end the IP address of
the new container will be printed. You can login via SSH to the `root`
user.

Password authentication is disabled; you must use SSH public key
authentication. The default configuration will use the same SSH keys
as you used for the root Proxmox user (`/root/.ssh/authorized_keys`).

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_container.sh)

{{< code file="/src/proxmox/proxmox_container.sh" language="shell" >}}

