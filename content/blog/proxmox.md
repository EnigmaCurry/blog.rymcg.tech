---
title: "k3s part 3: k3s on Proxmox"
date: 2020-11-12T12:49:02-08:00
draft: true
tags: ['k3s', 'proxmox']
---

## Abstract

 * [Proxmox](https://www.proxmox.com) (PVE) is an open source Debian based
   operating system that has built in support for running Virtual Machines and
   containers (KVM and/or LXC). Think of VMWare server, but free and open
   source.
 * You will install Proxmox on a bare-metal server you own or rent.
 * You will harden the SSH and firewall policies.
 * You will setup three virtual machines to create a k3s cluster. This way you
   can create a multi-node cluster, without actually needing multiple computers.
 * This is not a replacement for a true high-availability setup, but not only
   useful for testing environments, this can be a way to "carve out" a single
   large box into multiple smaller nodes and utilize a bare-metal server more
   like a self-hosted "cloud" service, and be able to destroy and recreate nodes
   more easily.
 * Everything is wrapped into an ansible playbook for ease of execution.
 * Everything will still be explained in detail in this post. You may also find
the [proxmox admin guide](https://www.proxmox.com/en/downloads/item/proxmox-ve-admin-guide-for-6-x) useful for even more context.
 
## Preparation

You will need:

 * A bare metal amd64 computer to dedicate to your Proxmox use.
 * A USB thumb drive to temporarily store the installer .iso file.
 * An ethernet cable to plug into your LAN (wireless is out of scope for this
   article, but it might work in a pinch.)
 * Mouse, Keyboard, and Monitor to use only during install. If you're seting up
   a remote server, you can use IPMI or a serial console. (technology not
   covered in this post.)
 * Download the [latest release of the Proxmox .iso
   Installer](https://www.proxmox.com/en/downloads/category/iso-images-pve).
   (6.2 as of Nov 2020.)
 
## Copy the iso image to USB

If your workstation isn't running Linux natively (or even if you are), you could
use a cross-platform app called [Etcher](https://www.balena.io/etcher/) to copy
the Proxmox installer to your USB drive. If you're using Linux (or other unix)
natively, you can just use `dd`:

Plug your usb drive into your workstation and list all of the block devices:

```
lsblk | grep disk
```

This next command assumes your USB device name is `sdb`. **Make sure you change
this name for whatever device YOUR usb drive uses** Find the path to your .iso
that you downloaded. Now run `dd` to burn the iso to the usb:

```bash
USB_DEV=sdb
ISO_IMAGE=~/Downloads/proxmox-ve_6.2-1.iso
sudo dd if=${ISO_IMAGE} of=/dev/${USB_DEV} status=progress
```

Once this command is complete, you can remove the USB device from your
workstation.

## Install proxmox

Get your keyboard, mouse, and monitor plugged into your proxmox device, plug in
the usb drive, and turn the computer on. In order to boot from the usb device,
you may need to configure your BIOS/UEFI boot order, or hold down a special key
during bootup. Once booted, you will be greeted with the Promox installer
wizard.

Follow the installer prompts:
 * Set your password
 * Pick your region info
 * Choose your hard disk to install to
 * Configure networking, you must set a static IP address for the server.

You can download the [proxmox admin
guide](https://www.proxmox.com/en/downloads/item/proxmox-ve-admin-guide-for-6-x)
for more detailed instructions.

Once finished, it will reboot, you can unplug the USB drive and the
keyboard/mouse/monitor as you shouldn't need them any more.

## Setup ansible client

You will need Ansible installed on your workstation. Follow the [Ansible Install
    Guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html).
    You should just be able to install this with your package manager, but check
    to make sure its a recent version.

Setup your workstation SSH config, adding an entry for the proxmox server. Edit
`$HOME/.ssh/config` and add this to the end:

```
Host proxmox1
     Hostname 10.13.13.11
     User root
```

You should keep the `Host` parameter as `proxmox1`. If you want to change it,
you will also need to edit a few other files (See `grep -R proxmox1`) that are
hardcoded expecting this SSH hostname. (Note that the actual proxmox hostname
can be whatever you want, this is just a local SSH alias.) You need to change
the `Hostname` parameter to be the real hostname (assuming it has a DNS entry)
or the IP address of the server.

If you don't yet have an SSH key on your workstation (`$HOME/.ssh/id_rsa`),
create one by running `ssh-keygen`.

From your workstation, install your SSH key:

```
ssh-copy-id proxmox1
```

You will need to enter the root password for the server once, this will copy
your SSH key (`~/.ssh/id_rsa.pub`) into the server's `~/.ssh/authorized_keys`
file, and this allows you to SSH into the server without needing a password from
now on.

You can test your key by running this (shouldn't require a password now):

```
ssh proxmox1 echo "Hi from $(hostname), ssh works!"
```

## Ansible playbook

Now that you have your ssh key setup, all the rest of the configuration is
performed via `ansible-playbook`, configured and executed from your workstation.
In fact, you should never need to use the proxmox dashboard at all. The
dashboard is still useful for some tasks, especially getting an overview of your
server, however when needing to make a change, you should prefer making the
change via ansible, and committed to git, so as to maintain a fully reproducible
setup.

Clone the repository containing the playbook (it is in the same repo that
contains this whole blog, the root of the ansible project is in the
`src/proxmox` directory) :

```bash
DIR=${HOME}/git/vendor/enigmacurry
mkdir -p ${DIR}
git clone git@github.com:EnigmaCurry/blog.rymcg.tech.git ${DIR}
cd ${DIR}/src/proxmox
echo "Proxmox Ansible directory is: $(realpath $(pwd))"
```

Here are the list of important files, that you (may) need to edit:

 * `site.yml` - this is the main playbook, it contains a list of all of the
   roles to execute on the server. You can comment out any section you don't
   want to run (YAML comments use `#` at the start of any line). For example, if
   you were to comment this whole file, nothing will run on the server.
 
 * `inventory/hosts.yml` - this is the list of the SSH hosts to run ansible on,
   which in our case is just one server, so long as you configured SSH with the
   suggested name `proxmox1` you can ignore this file.
