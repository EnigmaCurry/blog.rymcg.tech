---
title: nixos-vm-template
---

# nixos-vm-template

[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template) is a
tool for building and managing NixOS virtual machines with a focus on
immutability and reproducibility. It supports multiple backends (libvirt
for local development, Proxmox for server infrastructure) and provides a
unified interface for creating, upgrading, and managing VMs.

The core design uses an immutable architecture: a read-only root filesystem
containing the NixOS system, with mutable state isolated on a separate
`/var` disk. Multiple VMs can share a single base image through QCOW2
backing files, and upgrades happen by replacing the boot image while
preserving all data. This makes VMs reproducible, easy to roll back, and
resistant to filesystem corruption.

For cases where you need a fully writable system - NixOS experimentation,
Nix development, or learning - the tool also supports mutable VMs with a
single read-write disk and the full nix toolchain available.

In [part one: Running code agents in an immutable NixOS
VM](/blog/linux/code-agent-vm/), we set up a development VM on a laptop
using libvirt, configure Claude Code or Open Code inside the VM, and
establish a git-based workflow for testing the agent's work on other
machines. We also cover TRAMP for remote editing with Emacs.

In [part two: Bootstrapping a Docker server with immutable NixOS on
Proxmox](/blog/linux/nixos-proxmox-vm/), we deploy VMs to a Proxmox server
instead of local libvirt. We walk through the Proxmox backend
configuration, create a Docker server VM, and cover firewall rules,
snapshots, backups, and the identity sync mechanism.

In [part three: Mutable VMs are cool too](/blog/linux/mutable-vms/), we
introduce mutable VM support for interactive NixOS development. We discuss
the tradeoffs between immutable and mutable architectures, how to create
and upgrade mutable VMs, and when to use each approach.

In [part four: Managing VMs with home-manager and
sway-home](/blog/linux/nixos-vm-home-manager/), we integrate
nixos-vm-template into a home-manager workflow using sway-home. We cover
the `vm` alias, the nix store binding, creating backend-specific aliases
for Proxmox, and disk space reclamation with garbage collection.

{{< about_footer >}}
