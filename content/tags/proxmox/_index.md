---
title: proxmox
---

# Proxmox

[Proxmox VE](https://www.proxmox.com/en/proxmox-ve) is an open source
Virtual Machine hypervisor Operating System, built on top of Debian
Linux. It has a fully programmable API, can operate as a cluster, and
can behave as your own self-hosted mini cloud, for compute and
storage. Proxmox excels as an agile research and development
environment, making it easy to create new virtual machines, whenever
you have new ideas to try, or to automate resources as part of a
script. New VMs are auto-configured from
[cloud-init](https://cloudinit.readthedocs.io/en/latest/),
pre-provisioning your SSH keys, making it really feel similar to
creating a Droplet on DigitalOcean, except that it is all running on
your own self-hosted hardware.

Proxmox is also a good choice for certain production roles: if you
have a relatively small number of very large computers, Proxmox can
help you to "carve out" the larger machines into smaller VMs. It
should be stressed however, that if you do run all your
docker/kubernetes nodes on the same physical host, you are not
protected from hardware or network failures. Large scale production
scenarios will likely be better served by installing a native
Kubernetes distribution (K3s) onto multiple bare-metal machines,
rather than using Proxmox. However, if you still need to use VMs, you
can still achieve High Availability with Proxmox by installing several
nodes, and forming a cluster.

Parts 1-3 of this series are as yet, unwritten, but will cover the
basic installation and setup of Proxmox. (there was an older series,
but I have moved it to the [virtual-proxmox](/tags/virtual-proxmox/)
tag, as it is not useful for the majority of bare-metal proxmox
installs.) For now, just reference [the main Proxmox docs for getting
started with
installation](https://pve.proxmox.com/pve-docs/chapter-pve-installation.html).

In [part four: Containers](/blog/proxmox/04-containers/) we discuss
Proxmox support for LXC containers, which are a lightweight
shared-kernel alternative to virtualized machines. Containers offer
quicker start up time and efficient resource utilization. Unlike
Docker containers, LXC containers are stateful and run systemd inside,
and offer the same lifecycle as if it were a VM.

In [part five: KVM and Cloud-Init](/blog/proxmox/05-kvm-templates) we
use a shell script to generate several KVM virtual machine templates
from various distributions, including Arch Linux, Debian, Ubuntu,
Fedora, and even FreeBSD (can't do that one with a container!)

In [part six: nftables home LAN router](/blog/proxmox/06-router) we
build a network router for the home LAN inside a KVM virtual machine using PCI passthrough for a
four port network interface, and install a nftables firewall, dnsmasq
DHCP server, and dnscrypt-proxy DNS server.

In [part seven: proxmox in
proxmox](/blog/proxmox/07-proxmox-in-proxmox) we install a virtual
proxmox inside of a native proxmox host. This is very useful for
testing purposes, where you can add a bunch of virtual disks and play
around with different ZFS pool configurations. Use the snapshot
feature to create restore points, especially helpful when writing
documentation about proxmox itself.

In [part eight: TrueNAS Core](/blog/proxmox/07-proxmox-in-proxmox) we
install TrueNAS Core as a Network Attached Storage service, useful for
sharing files, and for remounting via NFS to provision other VM disks
on the same proxmox host.

{{< about_footer >}}
