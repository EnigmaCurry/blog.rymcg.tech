---
title: "k3s part 3: Proxmox"
date: 2020-11-12T12:49:02-08:00
draft: true
tags: ['k3s', 'proxmox', 'ansible']
---

## Abstract

 * [Proxmox Virtual Environment](https://www.proxmox.com/en/proxmox-ve) (PVE) is
   an open source Debian based operating system that has built in support for
   running Virtual Machines and containers ([KVM](https://www.linux-kvm.org/)
   and/or [LXC](https://linuxcontainers.org/)). Think of VMWare server, but free
   and open source.
 * You will install Proxmox on a bare-metal server you own or rent. Can be on a
   public or private network, but the assumption is for public usage and security.
 * You will harden the SSH and firewall policies, suitable for public hosting.
   VMs will live on an internal network utilizing IP masquerading (NAT), and
   only requires a single public IP address.
 * You will setup three KVM virtual machines to create a [k3s](https://k3s.io)
   cluster. This way you can create a multi-node cluster, without actually
   needing multiple physical computers.
 * Setup is scripted from an [Ansible](https://www.ansible.com/) playbook for
   ease of execution and reproducible deployments.
 * In addition to this guide, you may also find the official [proxmox admin
guide](https://www.proxmox.com/en/downloads/item/proxmox-ve-admin-guide-for-6-x)
useful.
 
Since only one physical computer is used, this will not be a replacement for a
production high-availability setup. It is useful for development environments,
or as a way to "carve out" a single large box into multiple smaller nodes.
Essentially creating your own testing lab, or self-hosted "cloud" service, which
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
the Proxmox installer to your USB drive. If you are using native Linux (or other
unix), you can just use `dd` to transfer the image directly to the device:

Plug your usb drive into your workstation and list all of the block devices:

```
lsblk | grep disk
```

From the output, determine the name of your USB device based upon the reported
size (4th column). This next command assumes your USB device name is `sdb`.
**Make sure you change `USB_DEV` for whatever device YOUR usb drive uses.** Find
the path to your .iso that you downloaded and set `ISO_IMAGE`. Then run `dd` to
burn the iso image to the usb:



```bash
USB_DEV=sdb
ISO_IMAGE=~/Downloads/proxmox-ve_6.2-1.iso
```

```bash
sudo dd if=${ISO_IMAGE} of=/dev/${USB_DEV} status=progress
```

Once this command is complete, you can remove the USB device from your
workstation.

## Install Proxmox

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

Setup your workstation SSH config, adding an entry for the proxmox server, and
the three k3s nodes you will be creating. Edit `$HOME/.ssh/config` and add this,
changing all of the example IP addresses (`192.0.2.2`) the same way, replacing
them with the real IP address for your proxmox server or its DNS name:

```
Host proxmox1
     Hostname 192.0.2.2
     User root
Host k3s-201
     Hostname 192.0.2.2
     Port 2201
     User ubuntu
Host k3s-202
     Hostname 192.0.2.2
     Port 2202
     User ubuntu
Host k3s-203
     Hostname 192.0.2.2
     Port 2203
     User ubuntu
```

`proxmox1` is a local SSH alias for the proxmox server (the real proxmox
hostname can be whatever you want, but the alias is used for convenience inside
the ansible playbook.) `k3s-201`, `k3s-202`, `k3s-203` are the names of the
three VMs the playbook will create. All share the same IP address as the proxmox
server, but unique SSH port numbers.

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

 * [site.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/site.yml) -
   this is the main playbook, it contains a list of all of the roles to execute
   on the server. You can comment out any section you don't want to run (YAML
   comments use `#` at the start of any line). For example, if you were to
   comment this whole file, nothing will run on the server.
 
 * [inventory/host_vars/proxmox1/variables.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/inventory/host_vars/proxmox1/variables.yml) -
   this is the proxmox host and network configuration.
   
 * [inventory/group_vars/proxmox/variables.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/inventory/group_vars/proxmox/variables.yml) -
   this is the general VM default settings.
 
 * [inventory/hosts.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/inventory/hosts.yml) -
   this is the list of the SSH hosts to run ansible on. As long as you
   configured SSH as per the above instructions, with the suggested aliases
   `proxmox1`, `k3s-201`, `k3s-202`, and `k3s-203`, then you can ignore this
   file.
   
 * [roles/kvm_k3s_vms/tasks/main.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/roles/kvm_k3s_vms/tasks/main.yml) -
   this is the role that sets up the VMs used for k3s.

 * `inventory/group_vars/proxmox/vault.yml` - this is an encrypted configuration
   (vault), containing secrets, it will be created in the next step.


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

## Default VM SSH keys (copy from your $HOME/.ssh/id_rsa.pub):
vault_core_ssh_keys:
  - "ssh-rsa your-long-ssh-public-key-here"
  - "ssh-rsa your-second-long-ssh-public-key-here"
  
## SSH host alias (same name as configured in $HOME/.ssh/config)
vault_proxmox_ansible_host: proxmox1
## Proxmox real server host name:
vault_proxmox_master_node: pve-east-1
## Proxmox cluster name:
vault_proxmox_cluster: pve

## Network
# domain without the hostname part
vault_proxmox_domain: pve.rymcg.tech
# primary public network interface name
vault_proxmox_public_interface: eno1
# private VM bridge interface name (will be created)
vault_proxmox_trunk_interface: vmbr0
# public ip address assigned to public interface
vault_proxmox_master_ip: 192.0.2.2
vault_proxmox_public_netmask: 255.255.255.0
vault_proxmox_public_gateway: 192.0.2.1
# CIDR notated public network/mask
vault_proxmox_public_network: 192.0.2.0/24
# first two octets of the private VM IP address space (/16 network)
vault_proxmox_trunk_ip_prefix: 10.10

## Serve API to localhost only by default:
vault_proxmox_external_client_subnets: []
# no ssl verification is necessary when API is localhost only:
vault_proxmox_client_verify_ssl: False
```

**Important Note**

Throughout the rest of the playbook, these values are referenced without the
`vault_` prefix. (Refer to
[inventory/host_vars/proxmox1/variables.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/inventory/host_vars/proxmox1/variables.yml)
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

Each block of VMs has a /24 subnet (ID range 100 is `10.10.1.0/24`, 200 is
`10.10.2.0/24`, etc). VM IP addresses are assigned deterministicly (static) based
upon the VM ID. For example:

 * VM ID 100 translates to the ip `10.10.1.100` (network `10.10.1.0/24`)
 * VM ID 201 translates to the ip `10.10.2.101` (network `10.10.2.0/24`)
 * VM ID 299 translates to the ip `10.10.2.199` (network `10.10.2.0/24`)
 * VM ID 999 translates to the ip `10.10.9.199` (network `10.10.9.0/24`)

Note that last octet is never below 100 and never more than 199. (100 IPs. The
rest of the IPs in each subnet are reserved.) The entire /16 subnet is assigned
to the trunk interface (`10.10.0.0` -> `10.10.255.255`). Note that the `10.10`
prefix can be changed to something else in your vault configuration.
   
## k3s VM creation

The `kvm_k3s_vms` role will create three Ubuntu 20.04 nodes for a k3s cluster.
Look at
[roles/kvm_k3s_vms/tasks/main.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/roles/kvm_k3s_vms/tasks/main.yml),
a VM is created declaratively by using this syntax (example of a single node
creation):

```
- name: Create k3s node 201
  include_role:
    name: kvm_instance
  vars:
    id: 201
    host: "{{ proxmox_master_node }}"
    user: root
    name: k3s-201
    size: m1.small
    volumes:
      root: 20G
    sshkeys: "{{ core_ssh_keys }}"
```

This delegates to the `kvm_instance` role to do the actual instance creation,
but also defines custom variables particular to the instance such as host name,
volumes, and the instance size.

Explanation of `vars`:
 
 * `id` - The Proxmox VM ID - this is an integer that identifies the specific
   Virtual Machine. Minimum ID is 100. As explained above, the VM ID directly
   corresponds to the IP address it will have. The ID `201` will have the IP
   address `10.10.2.101`.
 * `host` - the hostname of the proxmox server, (`proxmox_master_node` set in
   your vault).
 * `user` - the default username to create in the VM. If not `root`, this user
   will be granted `sudo` privileges.
 * `name` - the hostname of the VM.
 * `size` - the size name as described in `proxmox_instance_sizes`, `m1.small`
   gives you 2GB of RAM and 2 virtual CPUs.
 * `volumes` - the names and sizes of all attached storage. You must set a `root`
   volume size.
 * `sshkeys` - the list of SSH keys to install into the `user` account inside the
   VM. Using the value `{{ core_ssh_keys }}` will install the default keys
   stored in the vault.

Review the list of `proxmox_instance_sizes` in
[inventory/group_vars/proxmox/variables.yml](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/inventory/group_vars/proxmox/variables.yml) -
These names are loosely based off of AWS EC2 instance sizes (eg `m1.large`,
`c1.medium`). Each size specifies the number of virtual CPUs and the amount of
RAM to assign to the VM. These are completly configurable, so you can make up
your own instance size names/configs and add them to the list.


## Run the playbook

Once everything is configured, run the playbook to setup everything:

```bash
ansible-playbook site.yml
```

Hopefully it runs to completion with no errors.

