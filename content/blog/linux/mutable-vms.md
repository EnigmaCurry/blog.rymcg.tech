---
title: "NixOS VMs part 3: Mutable VMs are cool too"
date: 2026-01-29T00:00:00-06:00
tags: ['linux', 'nixos', 'libvirt', 'proxmox', 'nixos-vm-template']
---

*This is part 3 of a series on [nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template):*
1. *[Running code agents in an immutable NixOS VM](/blog/linux/code-agent-vm/)*
2. *[Bootstrapping a Docker server with immutable NixOS on Proxmox](/blog/linux/nixos-proxmox-vm/)*
3. *Mutable VMs are cool too (this post)*
4. *[Managing VMs with home-manager and sway-home](/blog/linux/nixos-vm-home-manager/)*

---

The [nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template)
project has, so far, been only about immutable VMs: read-only root
filesystem, separate `/var` disk for state, atomic upgrades from the
host. It's a nice model. But sometimes you just want a normal NixOS
system that you can poke at from the inside.

This post introduces mutable VM support - a single read-write disk with
the full nix toolchain available. Same profiles, same tooling, different
architecture.

## Why mutable?

Immutable VMs are great for production-like workloads. The OS is
locked down, upgrades happen by replacing the boot image, and you can't
accidentally `rm -rf /` your way into trouble. But there are cases where
that rigidity gets in the way:

- **NixOS experimentation**: You want to run `nixos-rebuild switch`
  inside the VM to test configuration changes interactively.
- **Nix development**: You're working on Nix expressions and need
  `nix build`, `nix develop`, and friends to actually work.
- **Learning NixOS**: You want a sandbox where you can break things and
  fix them without rebuilding images on the host.
- **Quick iterations**: Sometimes you just want to `nix profile install`
  something and see if it works.

Immutable VMs don't support any of this. The nix toolchain requires a
writable `/nix/store` with a valid database, and that's fundamentally
incompatible with a read-only root. The old workaround was a `nix`
profile that used overlayfs to make `/nix` writable, but it was fragile
and didn't survive reboots cleanly.

Mutable VMs solve this properly: one disk, fully writable, standard
NixOS.

## The tradeoffs

Nothing is free. Here's what you give up:

| Feature               | Immutable                     | Mutable        |
|-----------------------|-------------------------------|----------------|
| Root filesystem       | Read-only                     | Read-write     |
| Disk layout           | Boot + var (two disks)        | Single disk    |
| Thin provisioning     | Yes (QCOW2 backing files)     | No (full copy) |
| Host upgrades         | `just upgrade`                | Not supported  |
| Corruption resistance | High (root can't be modified) | Normal         |
| Nix commands          | Limited                       | Full toolchain |

The big one is thin provisioning. With immutable VMs, multiple VMs
sharing the same profile share a single base image - each VM's boot disk
is just a delta. With mutable VMs, each one gets a full copy of the
image. If your base image is 4GB, every mutable VM is at least 4GB on
disk.

The other big one is upgrades. You can't run `just upgrade` on a mutable
VM. The whole point is that the system is managed from inside, so you
SSH in and run `nixos-rebuild switch` like you would on any NixOS
machine.

## Creating a mutable VM

Run the interactive create command:

```bash
just create
```

When prompted, enter the VM name and select your desired profiles
(e.g., `docker`, `dev`). The wizard will also ask whether you want a
mutable or immutable VM - select mutable mode when prompted.

Alternatively, you can enable mutable mode on an existing machine
config:

```bash
just mutable myvm      # prompts to enable/disable
just recreate myvm     # applies the change
```

The `just mutable` command shows you the current status, explains what
mutable mode does, and asks for confirmation. If you enable it, the next
`just create` or `just recreate` will build a mutable image.

This works on both backends - just set `BACKEND=proxmox` in your `.env`
file or environment before running `just create`.

## What's different inside

A mutable VM looks like a normal NixOS system. The root filesystem is
ext4 on a single disk, `/nix` is writable, and you can run any nix
command you want. But the VM still gets its identity from the machine
config files - hostname, SSH keys, firewall ports - just stored in
different locations.

| File                | Immutable location                 | Mutable location                |
|---------------------|------------------------------------|---------------------------------|
| Hostname            | `/var/identity/hostname`           | `/etc/hostname`                 |
| Machine ID          | `/var/identity/machine-id`         | `/etc/machine-id`               |
| SSH authorized keys | `/var/identity/*_authorized_keys`  | `/etc/ssh/authorized_keys.d/*`  |
| Firewall ports      | `/var/identity/tcp_ports`          | `/etc/firewall-ports/tcp_ports` |
| Root password hash  | `/var/identity/root_password_hash` | `/etc/root_password_hash`       |

On boot, systemd services read these files and apply them. The
`firewall-ports.service` opens the configured ports; the
`root-password.service` sets the root password from the hash file. Same
end result, different plumbing.

## Upgrading a mutable VM

Since the system is writable, you upgrade it the normal NixOS way:

```bash
just ssh admin@myvm

# Inside the VM
sudo nixos-rebuild switch --upgrade
```

Or if you have a flake:

```bash
sudo nixos-rebuild switch --flake github:you/your-config#myvm
```

You can also use `nix-env` for user-level package management, though
that's generally not recommended on NixOS.

If you try `just upgrade` on a mutable VM, it will error out and tell
you to upgrade from inside instead. This is intentional - the host
doesn't own the system configuration anymore, the VM does.

## Firewall and passwords

The machine config files (`machines/<name>/tcp_ports`, `udp_ports`,
`root_password_hash`) are copied into the image at creation time. If you
want to change them:

1. Edit the files in `machines/<name>/`
2. Run `just recreate <name>`

Or just edit them directly inside the VM:

```bash
# Add a new allowed port in the running VM:
echo "8080" | sudo tee -a /etc/firewall-ports/tcp_ports
sudo systemctl restart firewall-ports

# Change root password
sudo passwd root
```

Changes made inside the VM persist across reboots but won't be reflected
in the machine config on the host. If you recreate the VM, you'll get
whatever's in the host-side config.

## When to use which

**Use immutable VMs when:**
- Running services that don't need system-level changes
- You want atomic, host-driven upgrades
- Multiple VMs share the same base image
- You value the corruption resistance of a read-only root

**Use mutable VMs when:**
- Experimenting with NixOS configuration
- Developing Nix expressions
- Learning NixOS interactively
- You need `nix build`, `nix develop`, or `nixos-rebuild`

Both types use the same profiles, the same machine config structure, and
the same `just` commands for everything except upgrades. You can have
some VMs immutable and others mutable in the same setup.

## Conclusion

Mutable VMs fill a gap that immutable VMs couldn't: interactive NixOS
development and experimentation. You lose thin provisioning and
host-driven upgrades, but you gain a fully functional nix toolchain and
the ability to iterate on system configuration without rebuilding images.

For production-like workloads, immutable is still the way to go. For
learning, development, and experimentation, mutable VMs are cool too.
