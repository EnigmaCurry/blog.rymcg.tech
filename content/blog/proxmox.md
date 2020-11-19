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
 
## Preparation

You will need:

 * A bare metal amd64 computer to dedicate to your Proxmox use.
 * A USB thumb drive to temporarily store the installer .iso file.
 * An ethernet cable to plug into your LAN (wireless is out of scope for this
   article, but it might work in a pinch.)
 * Mouse, Keyboard, and Monitor to use only during install.
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
 * Configure networking, you must set a static IP address.

You can download the [proxmox admin
guide](https://www.proxmox.com/en/downloads/item/proxmox-ve-admin-guide-for-6-x)
for more detailed instructions.

Once finished, it will reboot, you can unplug the USB drive and the
keyboard/mouse/monitor as you shouldn't need them any more.

## Initial setup

From your workstation, you can do all of the rest of the setup, either by using
the browser admin interface, or through SSH. The administration panel is running
on port 8006 and is TLS encrypted, so the URL to access it is:
`https://proxmox:8006` where `proxmox` is the IP address or DNS name of your
proxmox machine. Make sure to type `https://` it will not work with `http://`.
Login as `root` and use the password you defined during install.

You will see that the certificate is invalid, because it is a self-signed
certificate. Just bypass the message (or `confirm the exception`) to access the
site.

As soon as you login, you will see a message:

```
No valid subscription - You do not have a valid subscription for this server. 
```

## Decommercialify Proxmox 

You may be wondering, `I thought this was Open Source ??? Why is there a nag
screen?` Yes, it is Free and Open Source, but the installer you used also
included some features that require a license. If you wish to support the
proxmox developers, you can get a paid license. Otherwise, you do not need these
features, and you can ignore the license message. You will need to click through
the nag screen each time you log in. However, you can also patch it, so the nag
screen never shows up, and remove all the enterprise stuff.

 * SSH to the proxmox box as root (eg `ssh root@proxmox`, or the proxmox ip
   address).
 * The file containing the nag screen is in
   `/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`.
   
This command will make a backup copy of this file, and make the change to
disable the nag screen:

```
cd /usr/share/javascript/proxmox-widget-toolkit/
cp proxmoxlib.js proxmoxlib.orig.js
sed "s/data.status !== 'Active'/false/" < proxmoxlib.orig.js > proxmoxlib.js
```

Now when you login to proxmox, you will no longer see any nag screen.

You should also remove the enterprise apt repository, and add the free apt
repository:

```
rm /etc/apt/sources.list.d/pve-enterprise.list
echo 'deb http://download.proxmox.com/debian stretch pve-no-subscription' > /etc/apt/sources.list.d/pve-no-subscription.list
apt-update
```

## Harden SSH security

You should install your SSH keys to access the root account, and turn off
password authentication. From your workstation, make sure you have generated an
ssh key (`ssh-keygen`). 

From your workstation, copy your key to the proxmox server (replace `proxmox`
with the proxmox name or IP address):

```
ssh-copy-id root@proxmox
```

It will one time ask you for your root proxmox password.

Once the key is added, you can now login to proxmox without needing to enter a
password:

```
ssh root@proxmox
```

If this worked, now you can remove the ability to login with passwords. Edit the
`/etc/ssh/sshd_config` file, with nano or vim or whatever. At the very top of
the file, write a new line that says:

```
PasswordAuthentication no
```

Save the file, and then restart the ssh server:

```bash
systemctl restart sshd
```

## Firewall

By default, the proxmox firewall is completely off, allowing all traffic in and
out. This means anyone can access the proxmox dashboard (still password
protected).

Additionally, unless you're planning on [getting a trusted TLS certificate to
replace the self-signed
certificate](https://pve.proxmox.com/wiki/Certificate_Management), you cannot
trust that the certificate is always valid, and therefore run the risk of a
man-in-the-middle attack. It would be better if the proxmox dashboard were
blocked publicly, but allowed to forward through an SSH tunnel. This way, only
those with valid SSH keys can access the dashboard, and you move the trust away
from the TLS certificate, instead toward the SSH host certificate (trust is
established locally in `~/.ssh/known_hosts` the first time you connect, you'll
still get the certificate error in the browser though.)

To turn on the firewall, you need to create a new file on the server called
`/etc/pve/firewall/cluster.fw`. To create it, run:

```bash
cat <<EOF > /etc/pve/firewall/cluster.fw
[OPTIONS]

enable: 1

[RULES]

IN SSH(ACCEPT) -i vmbr0 -log info
EOF
```

The firewall automatically reloads when you create or save this file.

Try and reopen the page in your browser, and it should now fail to load.

From your workstation, setup an ssh tunnel like this:

```bash
ssh -NL 8006:localhost:8006 root@proxmox &
```

Then access https://localhost:8006 in the browser.

## Cloud-init

The easiest way to configure VMs with proxmox is with
[cloud-init](https://pve.proxmox.com/wiki/Cloud-Init_Support). cloud-init will
let you clone VMs from a common base image, and inject customizations into the
cloned copy on first boot.

```bash
apt-get install -y cloud-init

## Download latest ubuntu 20.04 cloud image (focal):
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img

## Create the template VM:
qm create 9000 \
    --name "Ubuntu 20.04" \
    --memory 2048 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --scsi0 local-lvm:vm-9000-disk-0 \
    --ide2 local-lvm:cloudinit \
    --boot c \
    --bootdisk scsi0 \
    --serial0 socket \
    --vga serial0

## import the downloaded disk to local-lvm storage
qm importdisk 9000 focal-server-cloudimg-amd64.img local-lvm

## Convert the image to a template:
qm template 9000
```

Now you can start VMs that are clones of VM 9000. 

It's easiest to create new VMs from the dashboard:

 * In the left-hand menu, find the VM template labeled `9000 (Ubuntu-20.04)`
 * Right click it, and select `Clone`
 * Select a new VM ID (defaults to next available)
 * Choose a new name
 * Keep the Mode set as `Linked Clone` (a linked clone is a copy-on-write clone,
   and is more efficient with disk space.)
 * Click `Clone`
 * Find the new VM in the list, click it and find the `Cloud-Init` tab for the VM.
 * Double-click on `SSH public key` and paste in your workstation SSH key
   (usually `~/.ssh/id_rsa.pub`)
 * Click `Start` to start the VM.
 
 
