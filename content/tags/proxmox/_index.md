---
title: proxmox
---

# Proxmox and virtualized Kubernetes

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
should be stressed however, that if you do run all of your kubernetes
nodes on the same physical host, you are not protected from hardware
or network failures. Large scale production scenarios will likely be
better served by installing a native Kubernetes distribution (K3s)
onto multiple bare-metal machines, rather than using Proxmox. However,
you can still achieve High Availability with Proxmox by installing
several nodes, and forming a cluster.

Yo dawg, you can run Proxmox inside another virtual machine, through
*nested virtualization*. In [part one: Virtual
Proxmox](/blog/proxmox/01-virtual-proxmox/), you will learn how to
install Proxmox on any Linux computer (inside of an existing operating
system). Proxmox itself will be running in a KVM virtual machine. (Or
you can skip this step and install on real hardware.) On top of
Proxmox, you will prepare an Ubuntu VM template, configuring the
default VM size (cpu+memory+storage), and adding your SSH keys for
cloud-init. You can clone new VMs using the template anytime (and
there's a REST API!), thus setting up your first Virtual Proxmox
development cloud. Finally, you will create a small
[K3s](https://k3s.io) Kubernetes cluster using two or three of these
nested Proxmox KVM nodes, and you can use this for your local
development environment.

In [part four: Containers](/blog/proxmox/04-containers/) we discuss
Proxmox support for LXC containers, which are a lightweight
shared-kernel alternative to virtualized machines. Containers offer
quicker start up time and efficient resource utilization. Unlike
Docker containers, LXC containers are stateful and run systemd inside,
and offer the same lifecycle as if it were a VM.

{{< about_footer >}}
