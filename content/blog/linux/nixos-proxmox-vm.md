---
title: "Bootstrapping a Docker server with immutable NixOS on Proxmox"
date: 2026-01-23T23:00:00-06:00
tags: ['linux', 'nixos', 'proxmox', 'docker']
---

*This is part 2 of a series on [nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template):*
1. *[Running code agents in an immutable NixOS VM](/blog/linux/code-agent-vm/)*
2. *Bootstrapping a Docker server with immutable NixOS on Proxmox (this post)*
3. *[Mutable VMs are cool too](/blog/linux/mutable-vms/)*
4. *[Managing VMs with home-manager and sway-home](/blog/linux/nixos-vm-home-manager/)*

---

In the [last
post](http://blog.rymcg.tech/blog/linux/code-agent-vm/) I
described running AI code agents inside immutable NixOS VMs using
libvirt on a laptop. That setup works well for local development, but
sometimes you want to deploy VMs on actual infrastructure - a Proxmox
server sitting in a closet, a rack, or someone else's datacenter.

The
[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template)
project now supports multiple backends. You build the same NixOS
images locally on your workstation, you run the same commands as you
would with libvirt, and you get the same immutable VMs - the only
difference is where they land. This post walks through using the
Proxmox backend to bootstrap a Docker server VM.

## Why Proxmox?

Libvirt is fine for laptops and 'sworkstations'. You run `just
create`, the VM shows up locally, and you SSH into it. But if you want
VMs running 24/7 on dedicated hardware, you probably have a hypervisor
already, and in the homelab world that hypervisor is usually Proxmox.

The new Proxmox backend builds images locally with Nix, then ships
them to your PVE node over SSH. No Proxmox API tokens, no web UI
clicking, no cloud-init templates. Just NixOS config, SSH, and `qm`.

## The backend abstraction

The tool now has a `BACKEND` variable. Set it to `libvirt` or
`proxmox` and the same Justfile recipes work against either target:

```bash
# Local libvirt (the default)
just create myvm docker 4096 2

# Remote Proxmox
BACKEND=proxmox just create myvm docker 4096 2
```

You can also put `BACKEND=proxmox` in a `.env` file and forget about
it. The commands are identical - `just start`, `just stop`, `just
upgrade`, `just ssh` - they just talk to different backends.

## Set up the Proxmox connection

All you need is SSH access to your PVE node. Create a `.env` file in
the project root:

```bash
BACKEND=proxmox
PVE_HOST=pve
PVE_NODE=pve
PVE_STORAGE=local-zfs
PVE_BRIDGE=vmbr0
PVE_DISK_FORMAT=raw
PVE_BACKUP_STORAGE=pbs
```

A few notes on these:

- `BACKEND` must be set to proxmox, otherwise libvirt is the default.
- `PVE_HOST` must be the name of the SSH config entry in your `~/.ssh/config`.
- `PVE_NODE` must match your Proxmox node's actual hostname. If your
  node is called `pve` in the web UI, put `pve` here.
- `PVE_STORAGE` is which storage system the VM disks get stored on
  (i.e., `local`, `local-zfs`, `my-nfs`).
- `PVE_BRIDGE` is the default network bridge. You can override this
  per-VM.
- `PVE_DISK_FORMAT` use `raw` format for ZFS or LVM-thin, `qcow2` for
  directory/NFS storage.
- `PVE_BACKUP_STORAGE` is optional, for vzdump backups. Point it at a
  PBS instance if you have one.

Make sure you can SSH to the PVE node. Use a key without a password,
or make sure that your SSH agent is loaded so you don't need to type
the password:

```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.1.100
```

If that works, you're good.

## Build and create the Docker VM

The project ships with composable mixin profiles. The `docker` profile
includes the Docker daemon and adds users to the `docker` group. For a
dedicated Docker server, you don't need the development tools or the
AI agents that we used in the last post. The `docker` profile gives
you a minimal system with SSH, Docker, and not much else (the `core`
profile is always implicitly included):

```bash
just build docker
```

This produces a NixOS image with a read-only root filesystem, and
Docker enabled. Now create a VM from it. Technically, the build step
is optional, because the create command will do it implicitly anyway:

```bash
just create apps01 docker 4096 2 50G bridge:vmbr0
```

This creates a VM named `apps01` with 4GB RAM, 2 CPUs, a 50GB `/var`
disk, bridged networking on `vmbr0`, and a firewall. The image gets
built locally, transferred to your PVE node via rsync, and imported as
a Proxmox VM. The whole process is non-interactive.

The `bridge:vmbr0` syntax lets you specify a Proxmox bridge directly.

## First boot

```bash
just start apps01
just status apps01
```

The status command queries the QEMU guest agent for the VM's IP
address. Once it's up:

```bash
just ssh admin@apps01
```

You're now SSH'd into a minimal NixOS system with Docker running.
Verify it works:

```bash
docker run --rm hello-world
```

## Docker data persistence

The immutable root design means Docker's data directory
(`/var/lib/docker`) lives on the read-write `/var` disk. This is where
images, containers, volumes, and networks are stored. When you upgrade
the base image, all of this survives.

If you want to run containers with persistent data, use standard
Docker volumes, or you may use bind mounts from another directory
under `/var`.

## Firewall configuration

By default, ports 22, 80, and 443 are open. The firewall rules are
stored per-VM in `machines/<name>/tcp_ports` (one port per line). To
open additional ports:

```bash
echo "8080" >> machines/apps01/tcp_ports
just upgrade apps01
```

The upgrade syncs the new port list to the VM's identity files and
rebuilds the boot image, and automatically reboots.

Important note: The firewall rules are applied inside the VM *and* on
the Proxmox host. This is a defense-in-depth approach. However, this
also means that you should never manually touch the firewall config of
the VM on the Proxmox console. All firewall changes must happen in the
`machines/<name>/tcp_ports` and `machines/<name>/udp_ports` files, and
subsequently run `just upgrade`.

## Network options

Proxmox VMs can use any bridge configured on your PVE node. The
network mode is stored per-VM and can be changed after creation:

```bash
# Move to a different bridge
just network-config apps01 bridge:vmbr1
just upgrade apps01
```

For NAT (if your PVE node has a NAT bridge configured):

```bash
just network-config apps01 nat
just upgrade apps01
```

## Snapshots before risky changes

About to `docker system prune -a` and hoping you don't regret it?
Snapshot first:

```bash
just snapshot apps01 before-prune
```

If things go wrong:

```bash
just stop apps01
just restore-snapshot apps01 before-prune
just start apps01
```

## Backups

For proper backups (not just snapshots), the tool wraps Proxmox's
vzdump:

```bash
just backup apps01
```

This creates a compressed backup on your `PVE_BACKUP_STORAGE`. To
restore:

```bash
just restore-backup apps01
```

If you have a Proxmox Backup Server, point `PVE_BACKUP_STORAGE` at it
and you get incremental, deduplicated backups for free.

## Upgrades

The immutable design makes upgrades straightforward. Say you want to
add
[lazydocker](https://github.com/jesseduffield/lazydocker)
(A TUI manager for Docker). Edit the profile:

```nix
# profiles/docker.nix
{ config, pkgs, ... }:
{
  config = {
    virtualisation.docker.enable = true;
    users.users.${config.core.adminUser}.extraGroups = [ "docker" ];
    users.users.${config.core.regularUser}.extraGroups = [ "docker" ];

    environment.systemPackages = with pkgs; [
      lazydocker
    ];
  };
}
```

Then upgrade the VM:

```bash
just upgrade apps01
```

This rebuilds the image, syncs identity files, replaces the boot disk
on Proxmox, and restarts the VM. Your `/var` disk - including all
Docker data, volumes, and home directories - is untouched. The VM
comes back up with the app `lazydocker` available and all your
containers intact.

## Cloning

Need another Docker server with the same setup? Clone it:

```bash
just clone apps01 apps02

## Optionally specify new hardware config (but no disk resize):
## just clone apps01 apps03 4096 2 bridge:vmbr0
```

This makes a full clone of the VM on Proxmox, generates fresh identity
files (new hostname, machine-id, MAC address, SSH host keys), and
syncs them onto the cloned `/var` disk. You get an independent VM
that's otherwise identical to the original.

## Serial console

If networking is broken and SSH won't connect, you can attach to the
VM's serial console directly:

First you'll need to set the root password (root login is disabled
otherwise):

```bash
just passwd apps01
just upgrade apps01
```

Reboot, and you'll be able to login via the serial console:

```bash
just console apps01
```

This opens an SSH session to the Proxmox node and attaches to the VM's
serial port. You may need to press `Enter` to see the login prompt.
Exit with `Ctrl-O` (that's the letter O, not zero).

## Proxmox uses full clones of the disk image

Unlike the libvirt backend, which has thin provisioning of the boot
device, the Proxmox backend sends a full clone of the boot device for
each VM you create on Proxmox. This increases the disk space required
per VM by about 3 to 4 GB. You can run as many Docker servers as you
want from a single `just build docker`, but, on Proxmox, each `just
create` produces an independent VM with its own boot disk, its own
identity, and its own `/var` disk.

If you really do want thin provisioning of Proxmox VMs, you could use
nixos-vm-template to create the first VM, then turn that VM into a
Proxmox template, and then use the Proxmox clone feature in the
console, but then those clones would not be managed by
nixos-vm-template.

## Syncing identity files into /var

The Proxmox backend's identity sync is worth noting: during upgrades,
it mounts the `/var` disk on the PVE node using `qemu-nbd` and writes
identity files directly. No need to download a multi-gigabyte disk
just to update a hostname.

## Putting it together

Here's the full workflow for going from zero to a running Docker
server on Proxmox:

```bash
# One-time setup on your workstation:
git clone https://github.com/EnigmaCurry/nixos-vm-template
cd nixos-vm-template

cat > .env << 'EOF'
BACKEND=proxmox
PVE_HOST=pve
PVE_NODE=pve
PVE_STORAGE=local-zfs
PVE_DISK_FORMAT=raw
PVE_BRIDGE=vmbr0
EOF

# Build and deploy
just create apps01 docker 4096 2 50G bridge:vmbr0
just start apps01
just ssh admin@apps01

# On the VM
docker run -d --name nginx -p 80:80 nginx
```

Now you have an immutable NixOS machine for your Docker server,
running on your own Proxmox infrastructure, built from a declarative
Nix configuration, with snapshots and backups available, upgradeable
without losing data, plus even if you don't make backups, the whole
machine is reproducible from the Nix config in your git repository
(minus your data).
