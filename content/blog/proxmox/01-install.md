---
title: "Proxmox part 1: Installation and Setup"
date: 2022-05-04T00:00:00-06:00
tags: ['proxmox']
---

This post will detail how to install proxmox and perform the initial
configuration. This is an abbreviated supplement to [the main Proxmox
install
guide](https://pve.proxmox.com/pve-docs/chapter-pve-installation.html)

## Hardware requirements

 * x86_64 CPU architecture (Intel and/or AMD 64 bit)
   * VT-x (hardware acceleration for virtualization)
   * VT-d or "directed IO", for PCI passthrough support (optional)
 * Wired ethernet for your LAN/WAN

## Download Proxmox VE .iso image

[Download the latest Proxmox VE release
here](https://proxmox.com/en/downloads/proxmox-virtual-environment)

Write the image to a USB drive with `dd` or a tool like
[UNetbootin](https://unetbootin.github.io/)

## Install

Boot the USB drive installer in the target machine.

{{<img src="/img/proxmox/boot.png" alt="The proxmox installer boot menu">}}

Choose `Install Proxmox VE (Graphical)`

Click the Target `Options` button, and change the `Filesystem`:

 * If you have one drive, choose `zfs (RAID0)`
 * If you have two drives available, choose `zfs RAID1` mirror
 * If you have three or more, choose `zfs RAIDZ-1`.

Use this [ZFS size calculator](https://wintelguy.com/zfs-calc.pl) to
play around with various configurations.

{{<img src="/img/proxmox/hard-disk-options.png" alt="Hard Disk Options, showing zfs RAID0 selected">}}

 * Select your Country, Time zone, and Keyboard layout.
 * Choose a root password
 * Enter *your* real email address, so that you receive notifications.
   (TODO: Requires setup of SMTP server later)

{{<img src="/img/proxmox/network-configuration.png" alt="Network configuration, including Hostname, IP address, Gateway, and DNS">}}

 * Choose the primary / management network interface (NIC)
 * Choose the fully qualified domain (host) name
 * Set a *static* IP address (and reserve it with your LAN DHCP
   server, using the MAC address).
 * Enter the upstream LAN gateway IP address.
 * Enter the upstream LAN DNS server IP address.

 * Finish the installation
 * Reboot

## Login to the proxmox dashboard

 * Once the machine has rebooted, you will see the URL (and IP
   address) to access the dashboard printed on the console.
 * Load the URL in your web browser, login with the username `root`
   and the password you chose during installation.

## Setup SSH keys and secure properly

SSH is enabled by default, and you can login with the username `root`
and the password is the password you chose during install. Because
passwords are less secure than SSH keys, that's the next step: to
install your SSH key, and disable password authentication.

Create an SSH host entry in your workstation's `$HOME/.ssh/config`:

```bash
PROXMOX_IP_ADDRESS=192.168.X.X \
PROXMOX_HOST=pve \
cat << EOF >> ~/.ssh/config

Host ${PROXMOX_HOST}
     Hostname ${PROXMOX_IP_ADDRESS}
     User root

EOF
```

(Change the Hostname `192.168.X.X` to be the IP address of your Proxmox host.)

If you have not created an SSH identity on this workstation, you will need to
run `ssh-keygen`.
 * From your workstation, run `ssh-copy-id pve`, which will ask you to
   confirm the ssh key fingerprint, and for your remote password (chosen during
   install) to login to the Proxmox server via SSH. It will copy your SSH key to
   the server's `authorized_keys` file, which will allow all future logins to be
   by key based authentication, instead of by password.
 * SSH to the Proxmox host, run `ssh pve`. Ensure that no password is
   required (except perhaps for unlocking your key file). You will now be in the
   root account of Proxmox, be careful!
 * You need to edit the `/etc/ssh/sshd_config` file. The text editors `nano` and
   `vi` are installed by default, or you can install other editors, for example
   `apt install emacs-nox`.
 * Disable password authentication - search for the line that says
   `PasswordAuthentication yes`, which will be commented out with `#`. Remove
   the `#` to un-comment the line, and change the `yes` to a `no`.
 * Save `/etc/ssh/sshd_config` and close the editor.
 * Restart ssh, run: `systemctl restart sshd`
 * Exit the SSH session, and test logging in and out again still works, using
   your SSH key.
 * To test that `PasswordAuthentication` is really turned off, you can attempt
   to SSH again, with a bogus username, one that you know does not really exist:

```
$ ssh hunter1@pve
hunter1@192.168.122.177: Permission denied (publickey).
```

   The attempt should immediately fail and say `Permission denied (publickey)`, *and if it
   also does not ask you for a password*, then you have successfully turned off
   password authentication.

## Disable Enterprise features and enable Community repository (optional)

{{<img src="/img/proxmox/no-valid-subscription.png" alt="Nag screen which says No valid subscription">}}

By default, Proxmox expects that you are an enterprise, and that you have an
enterprise license for Proxmox. If you do, skip this section. However, you may
also use the Proxmox community version, without a license (and it is the same
.iso image installer and method for both versions.) To switch between these
versions, you must use different apt package repositories. 

If you wish to use Proxmox exclusively with the Community,
non-enterprise version, run this as root:

```bash
## Backup existing sources list for Proxmox
cp /etc/apt/sources.list.d/pve-enterprise.list \
  /etc/apt/sources.list.d/pve-enterprise.list.bak

## Disable enterprise repository by commenting it out
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list

## Add the no-subscription community repository
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > \
  /etc/apt/sources.list.d/pve-no-subscription.list

## Update the package lists
apt update

## Clear the cache to make the changes effective immediately
systemctl restart pveproxy.service
```

## Setup Firewall

Proxmox has a 3-tier layered firewall:

 * Datacenter - priority 3 - most general
 * Node - priority 2 - node specific
 * VM / Container - priority 1 - most specific

By default the firewall is turned off. To set everything up, run the
`proxmox_firewall.sh` script, which will reset the firewall rules,
create basic rules for SSH and Web console, and enable both the Node
and Datacenter firewalls:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_firewall.sh

chmod +x proxmox_firewall.sh
```

```bash
./proxmox_firewall.sh
```

 * This script will delete all of the existing firewall rules.
 * Confirm the prompt.
 * Enter the management interface: `vmbr0`.
 * Enter the allowed subnet for managers: `0.0.0.0/0` (the default
   allows access to anyone connected through the management interface,
   but you might want to further restrict this.)
 * It will enable the firewalls and create new rules for SSH (port 22)
   and the web console (port 8006).
 * You may re-run the script. It is idempotent.

```stdout
? This will reset the Node and Datacenter firewalls 
  and delete all existing rules.. Proceed? (y/N): y

Enter the management interface (e.g., vmbr0)
: vmbr0
Which subnet is allowed to access the management interface?
: 0.0.0.0/0

Deleting node firewall rule at position 2.
Deleting node firewall rule at position 1.
Deleting node firewall rule at position 0.
Allowing ICMP ping response from the management interface.
Allowing access to SSH (22) for the management interface.
Allowing access to Proxmox console (8006) for the management interface.
Enabling Node firewall.
Enabling Datacenter firewall.
```

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_firewall.sh)

{{< code file="/src/proxmox/proxmox_firewall.sh" language="shell" >}}
