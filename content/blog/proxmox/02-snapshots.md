---
title: "Proxmox part 2: Snapshots"
date: 2021-07-31T00:01:00-06:00
tags: ['proxmox']
---

## Introduction

In [Part 1](/blog/proxmox/01-virtual-proxmox/) of this series, you created an
Ubuntu VM template, and three KVM virtual machines (all cloned from the same
template) on your Virtual Proxmox host, and you joined all three nodes into a
single K3s cluster, using the same cluster token.

It is a special point in time when you have not yet installed anything on your
cluster. You can use Proxmox to make a snapshot of these VMs, and thus create a
restoration point in time, of a fresh default cluster, with no data. The ability
to rollback to this state is useful for rapidly iterating on an idea, and when a
fresh cluster state is needed, especially in order to repeatedly test
installation processes. To start from scratch, you can rollback your entire
cluster state, backwards in time, to this blank slate.

Proxmox lets you make a snapshot, either when the VM is running (including RAM
snapshot), or when the VM is shutdown (no RAM snapshot). If you rollback to a
running snapshot (with RAM), the VM will then be running. If you rollback to a
shutdown snapshot (no RAM), the VM will then be shutdown. Creating both sets of
snapshots gives you the greatest flexibility, one for both states, so you can
rollback to either.

## Proxmox VM ID numbering system

You should now be somewhat familiar with the Proxmox dashboard and with the VM
list, underneath the Server view (left-hand side of the screen). All of your VMs
are listed here. Following from the example cluster you created in part 1, you
should now have these VMs created and listed:

 * `101 (k3s-1-1)`
 * `102 (k3s-1-2)`
 * `103 (k3s-1-3)`
 * `9000 (Ubuntu 20.04)` (this is a VM template)

All Proxmox VMs have a numeric ID that is unique to a particular VM (you can't
create two VMs with the same ID, but you can re-use IDs of deleted VMs).

Its recommended to come up with your own numbering scheme for grouping related
VMs, and for distinguishing the importance of those VMs. For example:

 * `100-199` : use for temporary VMs, all with clean snapshots created. For short lived
   prototypes only!
 * `200-299` : use for system VMs, for things you always want to have running,
   to run system level services like DNS or prometheus. (you can use snapshots
   as a backup before an upgrade, but generally these will never be rolled
   back.)
 * `300-399` : use for whatever you want, maybe a development environment.
 * `400-499` : use for whatever you want, maybe a testing environment.
 * .... whatever you want.
 * `9000-9099` : use for Operating System VM templates, one for each
   distribution. (Must not contain ANY application or operating system state,
   having never before booted, nor having created SSH host keys. Cloud-init will
   be used to individuate cloned VMs from this template.)

Whatever system makes sense for you, use it. As far as I know, there is no
way to group VMs from within the Proxmox dashboard (but VMs do have a notes
field, which is something), so having a mental organization for these VM IDs will
help you in the long run to understand your whole system.

## Making snapshots for VM block 100

Now you will setup all of the 100 ID block to be like throw-away, disposable
VMs. Sure, you could always delete the VMs, and create a new cluster by cloning
new VMs from the Ubuntu template, just like you did in part 1, but then you
still have to install the K3s server and workers, copy the cluster token to the
workers, copy the cluster config to your workstation, and configure `kubectl`.
This all takes time, and if you need to reinstall often, this time adds up. It
is much faster if you can just rollback the underlying VMs to a state when the
cluster has just been created and first made available. Because the cluster has
been initialized, and due to it having a unique cluster token, these VMs now
hold a state and identity as members of a specific cluster, so you should not
create a template of these VMs. (If you need to create a new separate cluster,
you should clone new VMs from the Ubuntu template instead, as described in part
1.) Having a snapshot of your existing cluster will allow you to restore it back
to the time just after its creation, and repurpose it for a new iteration or
idea.

You can follow these instructions to create the snapshots from the Proxmox
dashboard (or you can wait and use the equivalent script at the bottom of this
post instead):

 * Go to the Proxmox dashboard, and find the first VM with ID 101.
 * Right click the VM ID, click `Shutdown`, wait for the green running icon to
   dissappear, indicating that the VM is now shutdown.
 * Left click the VM ID, then click on Snapshots.
 * Click `Take Snapshot`.
 * Give it a descriptive name: `k3s_init_OFF`
 * The new snapshot is now in the list, with the RAM listed as `No`, which
   indicates that the VM snapshot is in the shutdown state, meaning that when
   the machines are rolled back to this state, they will be shutdown
   automatically.
 * Do the same process for the other VM IDs: 102 and 103.
 * Now turn all of the VMs on (101,102,103), and wait for them to boot up. Test
   that `kubectl get nodes` works and reports all nodes as `Ready`. While the
   VMs are still turned on, make a new set of snapshots for these VMs each named
   `k3s_init_ON`, (Make sure `Include RAM` is checked) this way you can restore
   the VM to a snapshot in either state (running or shutdown) depending on which
   snapshot name you choose to rollback to. These new snapshots will be listed
   with their `RAM` column set to `Yes`.

Any time you want to clear the state of this K3s cluster, you can go back to
this menu, click on the `k3s_init_OFF` (or `k3s_init_ON`) snapshot, and then
click the `Rollback` button. Do this for all the nodes: 101, 102, and 103. Then
you can start the nodes (if they are off) and the cluster will be like it was
freshly installed, and your workstation `kubectl` access will still work without
editing the config!

## BASH script for controlling the cluster VMs

You can do this process even faster if you don't use the dashboard, but use the
command line API instead. If you followed part 1, your workstation should have
setup SSH keys to login to the Proxmox server, as root. The following script
will let you access the [Proxmox CLI
commands](https://pve.proxmox.com/wiki/Command_line_tools) remotely, and will
manage all of your cluster VMs together as a group, with commands for `start`,
`stop`, `status`, `rollback`, and `snapshot`. Create a new file called `k3s-1`
and make sure to edit the config variables at the top of the script:

```
#!/bin/bash

## Save me as "cluster_name" and the make me executable:
##   chmod a+x cluster_name

# Edit this config for your specific cluster environment:
PROXMOX_SSH_HOST=proxmox
VM_IDS=(101 102 103)
VM_SNAPSHOT_ROLLBACK_OFF=k3s_init_OFF
VM_SNAPSHOT_ROLLBACK_ON=k3s_init_ON

start() {
    for VM_ID in "${VM_IDS[@]}"
    do
        echo "Starting ${VM_ID} ..."
        ssh $PROXMOX_SSH_HOST qm start ${VM_ID}
    done
}

stop() {
    for VM_ID in "${VM_IDS[@]}"
    do
        echo "Stopping ${VM_ID} ..."
        ssh $PROXMOX_SSH_HOST qm stop ${VM_ID}
    done
}

rollback() {
    local snapshot
    if [[ $1 == 'on' ]]; then
        snapshot=${VM_SNAPSHOT_ROLLBACK_ON}
    elif [[ $1 == 'off' ]]; then
        snapshot=${VM_SNAPSHOT_ROLLBACK_OFF}
    else
        snapshot=${VM_SNAPSHOT_ROLLBACK_OFF}
    fi
    for VM_ID in "${VM_IDS[@]}"
    do
        echo "Rolling back ${VM_ID} to snapshot '${snapshot}'..."
        ssh $PROXMOX_SSH_HOST qm rollback ${VM_ID} ${snapshot}
    done
}

snapshot() {
    local snapshot_name=${1:?Must provide a new snapshot name}
    for VM_ID in "${VM_IDS[@]}"
    do
        echo "Creating new snapshot for ${VM_ID}: '${snapshot_name}' ..."
        ssh $PROXMOX_SSH_HOST qm snapshot ${VM_ID} ${snapshot_name} --vmstate 1
    done
}

status() {
    for VM_ID in "${VM_IDS[@]}"
    do
        state=$(ssh $PROXMOX_SSH_HOST qm status ${VM_ID})
        echo "${VM_ID}: ${state}"
        ssh $PROXMOX_SSH_HOST qm listsnapshot ${VM_ID}
    done
}

main() {
    commands=(start stop status rollback snapshot)
    if ! echo ${commands[@]} | grep -q -w "$1"; then
        echo "Invalid command: $1"
        echo "Valid commands: ${commands[@]}"
        exit 1
    else
        $@
    fi
}

main $@
```

Make the script file executable:

```bash
chmod a+x k3s-1
```

You can move this script to someplace on your PATH, or you may drop it into any
particular project's directory, and run it locally.

To create the initial snapshots via the script (if you did not already create
them via the dashboard as described above):

 * Make sure your cluster is running and available, check by running: `kubectl
   get nodes` and ensure all the nodes are listed with `Ready` status.
 * Create the `ON` snapshot, run: `./k3s-1 snapshot k3s_init_ON` 
 * Shutdown the nodes, run: `./k3s-1 stop`
 * Create the `OFF` snapshot, run: `./k3s-1 snapshot k3s_init_OFF`

Now you can use any of these commands:

 * Check the running status of the VMs: `./k3s-1 status`
 * Start all VMs: `./k3s-1 start`
 * Stop all VMs: `./k3s-1 stop`
 * Create a new snapshot and name: `./k3s-1 snapshot [name]`
 * Rollback all the VMs:
   * Rollback to default `k3s_init_OFF` snapshot: `./k3s-1 rollback` (default)
     or `./k3s-1 rollback off`
   * Rollback to the `k3s_init_ON` snapshot: `./k3s-1 rollback on`
   * Rollback to any other snapshot name: `./k3s-1 rollback [name]`

