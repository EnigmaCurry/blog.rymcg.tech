---
title: "Proxmox part 4: Arch Linux container"
date: 2022-05-04T00:02:00-06:00
tags: ['proxmox']
---

Here is an automated script to install a fully updated Arch Linux
container (LXC) on Proxmox:

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/archlinux_container.sh)

{{< code file="/src/proxmox/archlinux_container.sh" language="shell" >}}

## Usage

Login to your Proxmox server as the root user via SSH.

Download the script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/archlinux_container.sh
```

Edit the variables at the top of the script.

Make the script executable:

```bash
chmod a+x archlinux_container.sh
```

And run it:

```bash
./archlinux_container.sh create
```

The container will be created, and at the very end the IP address of
the new container will be printed.

Password authentication is disabled; you must use SSH public key
authentication. The default configuration will use the same SSH keys
as you used for the root Proxmox user (`/root/.ssh/authorized_keys`).
