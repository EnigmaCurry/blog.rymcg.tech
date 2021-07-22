---
title: proxmox
---

# Proxmox

[Proxmox VE](https://www.proxmox.com/en/proxmox-ve) is an open source Virtual
Machine hypervisor Operating System, built on top of Debian Linux. It has a
fully programmable API, can operate as a cluster, and can behave as your own
self-hosted mini cloud, for compute and storage. Proxmox excels as an agile
research and development environment, making it easy to create new virtual
machines, whenever you have new ideas to try, or to automate resources as part
of a script. New VMs are auto-configured from
[cloud-init](https://cloudinit.readthedocs.io/en/latest/), pre-provisioning your
SSH keys, making it really feel similar to creating a Droplet on DigitalOcean,
except that it is all running on your own self-hosted hardware.

Proxmox is also a good choice for certain production roles: if you have a
relatively small number of very large computers, Proxmox can help you to "carve
out" the larger machines into smaller VMs. It should be stressed however, that
if you do run all of your kubernetes nodes on the same physical host, you are
not protected from hardware or network failures. Large scale production
scenarios will likely be better served by installing a native Kubernetes
distribution (K3s) onto multiple bare-metal machines, rather than using Proxmox.

Yo dawg, you can run Proxmox itself inside another virtual machine, through
*nested vitualization*. In the [first post of this
series](/blog/proxmox/01-virtual-proxmox/), you will learn how to install Proxmox
itself as a KVM virtual machine, on any Linux computer (on top of an existing
operating system), thus setting up your first Virtual Proxmox development environment.

{{< about_footer >}}
