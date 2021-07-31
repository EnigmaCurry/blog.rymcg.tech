---
title: "Proxmox part 1: Virtual Proxmox and K3s"
date: 2021-07-21T00:01:00-06:00
tags: ['proxmox']
---

This is the first post in the proxmox series, [read the introduction
first](/tags/proxmox).

## Virtual K3s Cluster in a Virtual Proxmox Host

If you want to have a virtual [K3s](https://k3s.io) cluster on your workstation,
you have a lot of options. This is just one way of doing it.
[Proxmox](https://www.proxmox.com/) is an Operating System that manages Virtual
Machines. Proxmox is designed to run on dedicated, bare-metal server hardware.
You can abuse it however, in a development environment, and get Proxmox to run
inside of another Virtual Machine host ([Qemu KVM +
libvirt](https://wiki.archlinux.org/title/QEMU)), running in your own user
environment, on an existing Linux laptop/workstation.

So, if you have a laptop, with a lot of free RAM and CPU, you can create a
virtual machine (libvirt), install Proxmox inside that VM, use Proxmox to create
several nested virtual machines, and install K3s worker nodes on those nested
VMs. (K3s VMs on Proxmox VM on Libvirt Host.)

This will also serve as a general introduction for installing and configuring
Proxmox, even for non-virtual environments, it is the same.

## Test for nested virtualization support:

To find out if your Linux host is capable of nested virtualization, run:

```bash
## Intel machine:
systool -m kvm_intel -v | grep -E "nested\W"
## AMD machine:
systool -m kvm_amd -v | grep -E "nested\W"
```

One of these lines should return : `nested = "Y"`

If the answer is not `Y`, read this [Arch wiki
section](https://wiki.archlinux.org/title/KVM#Nested_virtualization) for
enabling this support in your kernel.

## Install packages and start libvirt KVM service

On Arch Linux:

```bash
sudo pacman -S qemu libvirt libguestfs virt-manager \
    iptables-nft bridge-utils ebtables dnsmasq
sudo systemctl enable --now libvirtd.service
```

For other Linux distributions, you just need to install the same packages (the
names may be different), and start the libvirt service.

## Add your user to the libvirt group

```bash
sudo gpasswd -a ${USER} libvirt
```

## Create VM with virt-manager

`virt-manager` is a GUI frontend for the libvirt backend service, which will
allow you to create a virtual machine, boot from a `proxmox.iso` file, and
install Proxmox.

 * Download the latest version of [Proxmox VE ISO
   Installer](https://www.proxmox.com/en/downloads)
 * Run `virt-manager`
 * Click `File -> New Virtual Machine`
 * Follow through the wizard, clicking `Forward` on each page, reviewing to make
   sure you select all of the following options:
   * Select `Local install media (ISO image or CDROM)`
   * Choose the `ISO install media`, and click Browse to the install media file
   you downloaded.
   * Uncheck `Automatically detect from the installation media / source`, and
   enter `Generic Linux 2020` as the operating system type.
   * Choose appropriate Memory, CPU, and disk storage size, settings, depending on your specific
   hardware (Note this is for all of Proxmox and all of your k3s nodes combined).
   * Give your new machine an appropriate name, like `proxmox`.
   * Choose one of the Network selection types:
     * Choose `Virtual Network 'default': NAT` in order to provide NAT and DHCP
     to the Proxmox VM on a private subnet, so that the Proxmox installer should
     automatically detect all of the correct network IP address settings. You
     should still customize the new Hostname for Proxmox (default `pve`). The
     private subnet will route outgoing connections (eg. `curl` or `docker pull`
     initiated from inside a running VM), but it will not route incoming
     external connections by default (eg. you cannot `ssh` to a VM from an
     external network). The private subnet is accessible only between VMs and
     from the local host workstation, unless you add additional routing rules.
     * Or choose the `bridge` device, and bind it to another device name, if you
     wish Proxmox to communicate on the same network as the host itself. This
     will make additional DHCP requests on the same network as your host
     network, essentially assigning two IP addresses to the same primary network
     device (with different MACs), one for the host IP address, and one for the
     VM IP address, both in the same subnet on the same LAN. Use this mode to
     allow other hosts on your LAN full network access to the cluster running on
     your host. (You can use a local firewall to limit this access if you wish.)
     Note also that this mode requires elevated privileges, so unless you're
     running as `root`, and know what you're doing, stick to the `default`
     device instead, and then you can still create routes to the private subnet
     if you need to. Furthermore, if you are on a laptop binding to the wifi
     interface, consider the implications of new dhcp requests on foreign
     networks. The `default` NAT private subnet seems superior to `bridge` in
     almost every way.
 * Click `Finish` to commit the changes and create the VM.
 
The virtual machine should boot, and provide you the graphical terminal to
access it. 

 * On first boot of Proxmox, choose `Install Proxmox VE`
 * Click through the EULA.
 * The `Target Harddisk` should be automatically selected for the disk created
   by `virt-manager`, click `Next`.
 * Configure your time zone.
 * Choose a password and email address.
 * Click `Install` to finish installation. 
 * When finished, the virtual machine will reboot. Wait for, and watch through
   the first boot, until you see the login terminal.
   
On the terminal login screen, you will see the URL to connect to. For example:
`https://192.168.X.X:8006/` and please note that the `https://` and `:8006`
parts of the URL are important! Open this URL in your web browser. The TLS
certificate is self-signed by default, and so this will not be trusted by your
web browser, and it will show an error about that, but also it should show an
option for you to select that you want to proceed anyway. Now you should see the
web login screen for Proxmox.

 * You may close all the `virt-manager` windows, libvirt will continue to run
   your virtual machines in the background.

## Setup SSH keys and secure properly

You can login to the Proxmox terminal through SSH (no need for the
`virt-manager` terminal window ever again). The username is `root` and the
password is the password you chose during install. Because passwords are less
secure than SSH keys, that's the next step: to install your SSH key, and disable
password authentication.

Create an SSH host entry in your `$HOME/.ssh/config` file:

```
Host proxmox
    Hostname 192.168.X.X
    User root
```

(Change the Hostname `192.168.X.X` to be the IP address of your Proxmox virtual machine.)

If you have not created an SSH identity on this workstation, you will need to
run `ssh-keygen`. 
 * From your workstation, run `ssh-copy-id proxmox`, which will ask you to
   confirm the ssh key fingerprint, and for your remote password (chosen during
   install) to login to the Proxmox server via SSH. It will copy your SSH key to
   the server's `authorized_keys` file, which will allow all future logins to be
   by key based authentication, instead of by password.
 * SSH to the Proxmox host, run `ssh proxmox`. Ensure that no password is
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
$ ssh hunter1@proxmox-k3s-1
hunter1@192.168.122.177: Permission denied (publickey).
```

   The attempt should immediately fail and say `Permission denied (publickey)`, *and if it
   also does not ask you for a password*, then you have successfully turned off
   password authentication.

## Login to Proxmox web console

 * In the Proxmox web console, login with the username `root` and the password
   you chose during installation.
   
## Disable Enterprise features and enable Community repository (optional)

By default, Proxmox expects that you are an enterprise, and that you have an
enterprise license for Proxmox. If you do, skip this section. However, you may
also use the Proxmox community version, without a license (and it is the same
.iso image installer and method for both versions.) To switch between these
versions, you must use different apt package repositories. If you wish to use
Proxmox exclusively with the Community, non-enterprise version, follow the rest
of this section.

 * You will see a warning message `No valid subscription`, which will nag you on
   each login unless you purchase an enterprise edition of Proxmox. Click `OK`
   to freely use the community version.
 * On the left-hand side of the screen, find the `Server View` list, click the
   Proxmox host in the list.
 * Find the `Updates` and `Repositories` screen on the Node details screen.
 * Find the `pve-enterprise` repository in the list, and click it.
 * Click the `Disable` button at the top of the list.
 * You will see a message that says `No Proxmox VE repository is enabled.`
 * Click `Add`, it will nag you about the license again, just click `OK`.
 * Select `No-Subscription` in the Repository drop-down list, click `Add`.
 * You should now expect to to see this warning message: `The no-subscription
   repository is not recommended for production use`.

## Setup Firewall

By default the proxmox instance has an open firewall, but this can be made more
secure to only accept connections from specific sources, for example to lock
down to only being accessed from your workstation. This is particularly
important to do if you chose to use the `bridge` network selection, in
`virt-manager` when you created the VM.

 * In the `Server View` list, click the line that says `Datacenter`.
 * On the datacenter screen, find the `Firewall` settings.
 * Click the `Add` button to add firewall rules.
 * You don't need rules for SSH (TCP port 22) or for the Proxmox dashboard (TCP
   port 8006), these rules are already taken care of for you from the base
   system rules, as an anti-lockout feature.

The firewall is turned off by default. To enable the firewall, find the Firewall
`Options` submenu page, on the new screen double-click `Firewall` (value `No`)
at the top of the list. In the popup window, checkmark the box to enable the
firewall, then click `OK`. (The `Firewall` value should now show `Yes`).

## Create an Ubuntu cloud-init template

 * Open a terminal to the proxmox server (`ssh proxmox`)
 * Download the Ubuntu 20.04 LTS cloud image:
```bash
wget  http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
```
 * Create a new VM that will become a template:
```bash
qm create 9000
```

 * Import the cloud image as the primary drive:
```bash
qm importdisk 9000 focal-server-cloudimg-amd64.img local-lvm
```

   * You can delete the downloaded image now if you wish.
   
 * Configure the VM: 
```bash
qm set 9000 --name Ubuntu-20.04 --memory 2048 --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0 \
  --ide0 none,media=cdrom --ide2 local-lvm:cloudinit --boot c \
  --bootdisk scsi0 --serial0 socket --vga std --ciuser root \
  --sshkey $HOME/.ssh/authorized_keys --ipconfig0 ip=dhcp
```

 * Download the `gparted` ISO image, which is to be used to resize the disk:
```bash
wget -P /var/lib/vz/template/iso \
  https://downloads.sourceforge.net/gparted/gparted-live-1.3.0-1-amd64.iso
```

 * Set the first boot device to load `gparted`
```bash
qm set 9000 --ide0 local:iso/gparted-live-1.3.0-1-amd64.iso,media=cdrom \
  --boot 'order=ide0;scsi0'
```

 * Resize the disk, adding 50GB (or whatever size you prefer for your template):
```bash
qm resize 9000 scsi0 +50G
```

   
Go to the web console, and find VM 9000 in the list, then click `Start`. Click
`Console` in the node list, and Gparted will load on screen.

 * Follow the on screen setup instructions.
 * Once gparted loads, it will say `Not all of the space available to /dev/sda
   appears to be used,`. Click `Fix`.
 * Select `/dev/sda1`, right click and choose `Resize/Move`.
 * Click and drag the right hand side of the bar all the way to the right. (Free space before and after should both say 0, and with a new larger size listed.) Click `Resize/Move`.
 * Click `Edit -> Apply All Operations`, then `Apply`.
 * When finished click `Close`, then Shutdown the VM.
 
Remove the CD-ROM drive from the VM:

```bash
qm set 9000 --delete ide0
```

Remove the VGA adapter (no longer needed, now that gparted is done), and replace
it with a serial device:

```bash
qm set 9000 --vga serial0
```

Convert virtual machine to a template:

```bash
qm template 9000
```


## Create K3s nodes

Now that you have an Ubuntu template, you can create nodes for K3s workers:

 * From the web console, find VM 9000, right click it, and choose `Clone`.
 * Use the default mode: `Linked Clone` (the clone creates a [Copy on
   Write](https://en.wikipedia.org/wiki/Copy-on-write) volume, based off the
   original image: this will save you a ton of host disk space, if you create
   lots of clones that are mostly the same.)
 * Enter the name `k3s-1` (or whatever you want)
 * Click `Clone`.
 * Start the VM.
 * Repeat and clone for as many other worker nodes as you want.
 
Once the machine starts, wait for DHCP to assign an IP address. You can check
for the IP address on the host running libvirt (your workstation):

```bash
# Query DHCP leases on the host:
sudo cat /var/lib/libvirt/dnsmasq/virbr0.status
```

When you find the IP addresses, edit `$HOME/.ssh/config` and add a new section for
each of the nested VM hosts:

```
# Host SSH client config: ~/.ssh/config

Host proxmox-k3s-1
    Hostname 192.168.X.X
    User root
    
Host proxmox-k3s-2
    Hostname 192.168.X.X
    User root

```

Test login via ssh with your key: 

```bash
ssh proxmox-k3s-1
```

On the first node, install the k3s server:

```bash
# Install K3s server on first node:
curl -sfL https://get.k3s.io | sh -s - server --disable traefik
```

Retrieve the K3s cluster token:

```bash
cat /var/lib/rancher/k3s/server/node-token
```

On the second and rest of the nodes, install the k3s worker agent, filling in
the proper cluster token you retreived, and the IP address of the first (k3s
server) node:

```bash
# Install K3s worker agent: fill in K3S_URL and K3S_TOKEN
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.X.X:6443 K3S_TOKEN=xxxx sh
```

## Setup local workstation 

In order to access the k3s cluster from the host workstation, you need to copy
the config file:

```bash
# From your workstation:
mkdir -p $HOME/.kube && \
scp proxmox-k3s-1:/etc/rancher/k3s/k3s.yaml $HOME/.kube/proxmox-k3s && \
echo "export KUBECONFIG=$HOME/.kube/proxmox-k3s" >> $HOME/.bashrc && \
export KUBECONFIG=$HOME/.kube/proxmox-k3s
```

You now must edit `$HOME/.kube/proxmox-k3s` and replace `127.0.0.1` with the IP
address of the server node. Also search and replace for the word `default` and
replace it with the name of the cluster `k3s-1`. Save the file.

Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
and [helm](https://helm.sh/docs/intro/install/).

Test that `kubectl` works:

```bash
kubectl get nodes
```

If you have more than one `kubectl` config file, you can list multiple in your
`$HOME/.bashrc`, separated with colons:

```
export KUBECONFIG="$HOME/.kube/proxmox-k3s:$HOME/.kube/localhost-k3s"
```

Install the [kubectx](https://github.com/ahmetb/kubectx) tool for easy switching
between clusters (`kubectx`) and namespaces (`kubens`).

## Now you have a Virtual K3s cluster

The next post in this series will install Traefik, and generate a wildcard TLS
certificate using Let's Encrypt ACME DNS challenge (for certificate use beind
LAN firewall).

## Configure extra workstation niceties

All of these steps are optional, but improve the user experience:

 * Install the `bash-completion` package. On Arch Linux: 
 
```bash
sudo pacman -S bash-completion
```
 * Install the `kubectx` package. On Arch Linux:
 
```bash
sudo pacman -S kubectx
```
 * Install the [kube-ps1](https://github.com/jonmosco/kube-ps1) package. On Arch
   Linux you can install `kube-ps1` with an [AUR
   helper](https://wiki.archlinux.org/title/AUR_helpers).

 * Enable Bash completion, create `k` alias for kubectl, and configure your
   `PS1` prompt to show the current K8s context and namespace. Put this in your
   `$HOME/.bashrc` file:
 
```
## Enable bash completion:
if [ -f /etc/bash_completion ]; then
    source /etc/bash_completion
fi
## kubectl completion is automatically loaded 
## from /usr/share/bash-completion/completions/kubectl

## Alias k for kubectl:
alias k="kubectl"
complete -F __start_kubectl k

## Create PS1 prompt with current K8s context and namespace:
source '/opt/kube-ps1/kube-ps1.sh'
PS1='[\u@\h $(kube_ps1)] \W $ '

## List several separate context files in one KUBECONFIG, 
## separated with ':':
export KUBECONFIG="$HOME/.kube/k3s-1:$HOME/.kube/k3s-2"
```

 * Switch between contexts with `kubectx`.
 
 * Switch the default Kubernetes namespace: `kubens` (`kubens` is
   installed with `kubectx`)


