---
title: "Proxmox part 7: Proxmox in Proxmox"
date: 2023-11-18T00:01:00-06:00
tags: ['proxmox', 'virtual-proxmox']
---

In part 1 of the [virtual-proxmox](/tags/virtual-proxmox) series, we
installed proxmox on on a regular Linux desktop computer [inside of
KVM](https://blog.rymcg.tech/blog/proxmox/01-virtual-proxmox/) (Kernel
Virtual Machine). In this post, we will do something similar, but this
time we will install a virtual Proxmox inside of an existing Proxmox
server. This endeavour serves no practical production purpose, but may
be very useful for testing and/or documentation, both of which are
germane to this blog. This post also explores creating a Proxmox
cluster, which allows you to manage several Proxmox instances from a
single dashboard.

## Upload the proxmox iso image

On your existing Proxmox server, open the dashboard:

 * Click on the `local` storage (by default, or whatever storage you
   have that is tagged for ISO image use).
 * Click `ISO Images`
 * Click `Upload` and choose the `proxmox-ve_8.0-2.iso` (or similar)
   and upload it.

## Create a new VM

 * Right click on the proxmox server underneath the datacenter list.
 * Click `Create VM`
 * Give the VM a name: `pve-test`
 * Choose the proxmox ISO image you uploaded
 * Choose the disk size (default 32GB)
 * Give it some cores (2) and some RAM (8192)
 * Finalize the creation.

## Install Proxmox in the VM

Start the VM and open the console and finish the installation of
Proxmox. After rebooting, take note of the URL printed in the console,
and open it in your web browser to access the virtual proxmox
dashboard (`https://x.x.x.x:8006`). You must bypass the self-signed
certiticate the first time you open it.

## Create a Proxmox cluster

You can join both the native proxmox and the virtual proxmox together
into one cluster, and this way you will be able to manage both
instances under one dashboard.

 * Open the dashboard on your *native proxmox host*
 * Click on `Datacenter`
 * Click `Cluster`
 * Click `Create Cluster`
 * Enter any name for the cluster (eg. name it after the home
   location, as you may want to add all the servers around your home
   to this same cluster)
 * Finalize the creation of the cluster.
 * Click `Join information` and copy the join information.

## Join the virtual proxmox to the cluster

 * Open the dashboard on your *virtual proxmox instance*
 * Click on `Datacenter`
 * Click `Join Cluster`
 * Paste in the join information copied from the native dashboard
 * Enter the root password of the *host*
 * Click `Join [cluster]`

Now you will find the virtual instance has been populated on the
native host's dashboard. Find `pve-test` in the list under
`Datacenter`.

## Remove the virtual proxmox from the cluster

Log into the pve shell, and run:

```
pvecm nodes
```

You should see two nodes, 1) your native proxmox host 2) the virtual
proxmox host.

[According to the
documentation](https://pve.proxmox.com/wiki/Cluster_Manager#_remove_a_cluster_node),
here's how you remove the node:

 * Backup / Move all the VMs and data (although you probably haven't
   put anything important in there yet, so whatever).
 * Shutdown and disable the `pve-test` VM from starting on boot.
 * With one node missing from a two node cluster, you no longer have
   quruom to do most tasks. To regain quorum on the primary node, you
   must set the expected # of votes to 1, run:

```
pvecm expected 1
```

 * Remove the node from the cluster, run:

```
pvecm delnode pve-test
```

It should say `Killing node 2`. The docs also say that you can safely
ignore any error about `Could not kill node (error =
CS_ERR_NOT_EXIST)`, it is not really a failure.

 * Refresh the dashboard, and the `pve-test` node should be now be
   gone.
 * Click on `Datacenter`, and then `Cluster`, and you should see the
   cluster no longer shows the `pve-test` node.

## Add additional storage to the virtual instance

Virtual hard drives are hot swappable, so you can simply create and
attach as many virtual drives without needing to reboot.

 * Click the `pve-test` VM on the host server.
 * Click `Hardware`
 * Click `Add`
 * Click `Hard Disk`
 * Choose the storage pool and the size
 * Click `Add` to add the new disk.
 * Repeat this process, to add a total of two new virtual disks.

Find the new disk automatically recognized on the `pve-test` instance:

 * Under the `Datacenter` view, click `pve-test`
 * Click on `Disks`
 * See that the new disks are shown in the list
 * Under `Disks`, click `ZFS`
 * Click `Create ZFS`
 * Enter the name: `test`
 * Choose the RAID level: `mirror`
 * Select both of the new drives available in the list.
 * Click `Create`

Enjoy your virtual proxmox experience!
