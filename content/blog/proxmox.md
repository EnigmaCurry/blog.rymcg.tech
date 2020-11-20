---
title: "k3s part 3: k3s on Proxmox"
date: 2020-11-12T12:49:02-08:00
draft: true
tags: ['k3s', 'proxmox', 'ansible']
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
 * Setup is scripted with an ansible playbook for ease of execution.
 * In addition to this guide, you may also find the official [proxmox admin
guide](https://www.proxmox.com/en/downloads/item/proxmox-ve-admin-guide-for-6-x)
useful.
 
This will not be a replacement for a true high-availability setup, but it is
useful for testing environments, or as a way to "carve out" a single large box
into multiple smaller nodes, creating your own self-hosted "cloud" service, and
lets you create, destroy, and recreate VMs with ease.

## Preparation

You will need:

 * A bare metal amd64 computer to dedicate as your Proxmox server.
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
this name for whatever device YOUR usb drive uses.** Find the path to your .iso
that you downloaded. Now run `dd` to burn the iso to the usb:



```bash
USB_DEV=sdb
ISO_IMAGE=~/Downloads/proxmox-ve_6.2-1.iso
```

```bash
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
`$HOME/.ssh/config` and add this, changing the example IP address for your
proxmox server IP address or DNS name:

```
Host proxmox1
     Hostname 192.0.2.1
     User root
Host k3s-201
     Hostname 192.0.2.1
     Port 2201
     User ubuntu
Host k3s-202
     Hostname 192.0.2.1
     Port 2202
     User ubuntu
Host k3s-203
     Hostname 192.0.2.1
     Port 2203
     User ubuntu
```

You should keep the first `Host` parameter as `proxmox1`. If you want to change
it, you will also need to edit a few other files (See `grep -R proxmox1`) that
are hardcoded expecting this SSH hostname. (Note that the actual proxmox
hostname can be whatever you want, this is just a local SSH alias.) You need to
change the `Hostname` parameter to be the real hostname (assuming it has a DNS
entry) or the IP address of the server. `k3s-201`, `k3s-202`, `k3s-203` are the
names of VMs we will create. The `Hostname` for these should be the same public
IP address for the proxmox serer, the port number changes for each one.

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

Clone this repository containing the playbook (it is in the same repo that
contains this whole blog, the root of the ansible project is in the
`src/proxmox` directory) :

```bash
DIR=${HOME}/git/vendor/enigmacurry/blog.rymcg.tech
```

```bash
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
 
 * `inventory/host_vars/proxmox1/variables.yml` - this is the host
   configuration, containing network configuration and general VM default
   settings.
 
 * `inventory/hosts.yml` - this is the list of the SSH hosts to run ansible on,
   which in our case is just one server, so long as you configured SSH with the
   suggested name `proxmox1` you can ignore this file.

 * `inventory/group_vars/proxmox/vault.yml` - this is an encrypted configuration
   (vault), containing secrets, it will be created next.
   
 * `roles/kvm_k3s_vms/tasks/main.yml` - this is the role that sets up the VMs
   used for k3s. 

## Create Ansible Vault (secrets)

Create an ansible vault to store and encrypt the root proxmox password among
other secret values.

Run:

```
ansible-vault create inventory/group_vars/proxmox/vault.yml
```

Create a new passphrase to encrypt the vault.

Your default `$EDITOR` will open, in which to store the unencrypted vault
contents. Enter this text :

```
## Proxmox admin accounts CHANGE THESE PASSWORDS:
vault_proxmox_root: "root@pam"
vault_proxmox_root_password: "changeme"
vault_proxmox_kvm_admin: "root@pam"
## If kvm admin is root, use the same password as above:
vault_proxmox_kvm_admin_password: "changeme"

## Default VM SSH keys:
vault_core_ssh_keys:
  - "ssh-rsa your-long-ssh-public-key-here"
  - "ssh-rsa your-second-long-ssh-public-key-here"
  
## SSH host alias
vault_proxmox_ansible_host: proxmox1
## Proxmox real server host name:
vault_proxmox_master_node: pve-east-1
## Proxmox cluster name:
vault_proxmox_cluster: pve

## Network
# domain without the hostname
vault_proxmox_domain: pve.rymcg.tech
# primary public network interface name
vault_proxmox_public_interface: eno1
# VM bridge interface name (will be created)
vault_proxmox_trunk_interface: vmbr0
# public ip address assigned to public interface
vault_proxmox_master_ip: 192.0.2.2
vault_proxmox_public_netmask: 255.255.255.0
vault_proxmox_public_gateway: 192.0.2.1
# CIDR notated public network/mask
vault_proxmox_public_network: 192.0.2.0/24
# first two octets of the VM IP address space (/16 network)
vault_proxmox_trunk_ip_prefix: 10.10

## Serve API to localhost only by default:
vault_proxmox_external_client_subnets: []
vault_proxmox_client_verify_ssl: False
```

**Important Note**

Throughout the rest of the playbook, these values are referenced without the
`vault_` prefix. (Refer to
[inventory/host_vars/proxmox1/variables.yml](inventory/host_vars/proxmox1/variables.yml)
to see where these values are transformed into variables names without the
`vault_` prefix.)
 
Now you can double-check that the vault is encrypted:

```
cat inventory/group_vars/proxmox/vault.yml 
```

Which should look unreadable, something like:

```
$ANSIBLE_VAULT;1.1;AES256
34393966383135653437323561663465623539393239393662343035653161366633666365643065
3965343630366433653531663364393236376330353062660a616435636530373966373962663565
30643264373362633561363437396461636466643362626331323264616462373837373263616135
3863326139653364310a356534376637326136626134303138373264346566303430663661303537
35353961663662663437643262356566636536326332666630383038346564373064393538366334
3230303065623738363064613366626234633833653164363365
```

To decrypt and print the vault contents, run:

```
ansible-vault view inventory/group_vars/proxmox/vault.yml
```

To edit the vault, run:

```
ansible-vault edit inventory/group_vars/proxmox/vault.yml
```

This will re-open your editor, allowing you to make changes. Save the file and
close the editor, and the vault will be safely re-encrypted.

## Configure host_vars and networking

The network setup you did in the installer was only temporary, the ansible
playbook sets up new networking.

Each block of VMs has a /24 subnet (ID range 100 is 10.10.1.0/24, 200 is
10.10.2.0/24, etc). VM IP addresses are assigned automatically (static) based
upon the VM ID. For example:

 * VM ID 100 translates to the ip 10.10.1.100 (network 10.10.1.0/24)
 * VM ID 201 translates to the ip 10.10.2.101 (network 10.10.2.0/24)
 * VM ID 299 translates to the ip 10.10.2.199 (network 10.10.2.0/24)
 * VM ID 999 translates to the ip 10.10.9.199 (network 10.10.9.0/24)

Note that last octet is never below 100 and never more than 199. (100 IPs. The
rest of the IPs in each subnet are reserved.) The entire /16 subnet is assigned
to the trunk interface (10.10.0.0 -> 10.10.255.255)

Edit the file `inventory/host_vars/proxmox1/variables.yml`, review and change
the following:

 * `proxmox_master_node` - the real hostname of the server
 * `proxmox_domain` - the domain name (without the hostname)
 * `proxmox_public_interface` - the public ethernet device name
 * `proxmox_master_ip` - the IP address assigned to the public interface
 * `proxmox_public_gateway` - the IP address of the public gateway
 * `proxmox_public_network` - the CIDR notated network/mask of the public network.
 * `proxmox_trunk_ip_prefix` - the first two octets of the private VM IP
   addresses. Default is `10.10` for the address space `10.10.0.0` to
   `10.10.255.255`.
 * `proxmox_instance_sizes` - names for variously sized VMs. These are loosely
   based off of AWS instance sizes (eg `m1.large`, `c1.medium`). Each size
   specifies the number of virtual CPUs and the amount of RAM. These are
   completly configurable, so you can make up your own instance size
   names/configs and add them to the list.
   
## k3s VM creation

The `kvm_k3s_vms` role will create three Ubuntu 20.04 nodes for a k3s cluster.
Look at `roles/kvm_k3s_vms/tasks/main.yml`, a VM is created declaratively by
using this syntax (example of a single node):

```
- name: k3s node 201
  include_role:
    name: kvm_instance
  vars:
    id: 201
    host: proxmox1
    user: root
    name: k3s-201
    size: m1.small
    volumes:
      root: 20G
    sshkeys: "{{ core_ssh_keys }}"
```

Explanation of `vars`:
 
 * `id` The Proxmox VM ID - this is an integer that identifies the specific
   Virtual Machine. Minimum ID is 100. As explained above, the VM ID directly
   corresponds to the IP address it will have. The ID `201` will have the IP
   address `10.10.2.101`.
 * `host` the SSH hostname of the proxmox server.
 * `user` the default username to create in the VM. This use will have `sudo`
   privileges.
 * `name` the hostname of the VM.
 * `size` the size name as described in `proxmox_instance_sizes`, `m1.small`
   gives you 2GB of RAM and 2 virtual CPUs.
 * `volumes` the names and sizes of all attached storage. You must set a `root`
   volume size.
 * `sshkeys` the list of SSH keys to install into the `user` account inside the
   VM. Using the value `{{ core_ssh_keys }}` will install the default keys
   stored in the vault.

## Run the playbook

Once everything is configured, run the playbook to configure everything:

```bash
ansible-playbook site.yml
```

Hopefully it runs to completion with no errors.

