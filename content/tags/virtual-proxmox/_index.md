---
title: proxmox
---

# Virtual Proxmox

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


{{< about_footer >}}
