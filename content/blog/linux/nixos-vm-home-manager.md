---
title: "NixOS VMs part 4: Managing VMs with home-manager and sway-home"
date: 2026-01-29T00:00:01-06:00
tags: ['linux', 'nixos', 'libvirt', 'home-manager', 'nixos-vm-template']
---

*This is part 4 of a series on [nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template):*
1. *[Running code agents in an immutable NixOS VM](/blog/linux/code-agent-vm/)*
2. *[Bootstrapping a Docker server with immutable NixOS on Proxmox](/blog/linux/nixos-proxmox-vm/)*
3. *[Mutable VMs are cool too](/blog/linux/mutable-vms/)*
4. *Managing VMs with home-manager and sway-home (this post)*

---

The previous posts covered creating and managing VMs with
[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template). But
how do you actually integrate it into your daily workflow on your
workstation? This post covers using
[home-manager](https://github.com/nix-community/home-manager) to set up
the VM tooling, create shell aliases with tab completion, and manage
updates through the Nix ecosystem.

## What is home-manager?

[Home Manager](https://github.com/nix-community/home-manager) is a tool
for managing user environments using the Nix package manager. Instead of
manually installing programs and editing dotfiles, you declare what you
want in a Nix configuration file, and home-manager builds and activates
that environment.

The key benefits:

- **Declarative**: Your entire user environment is defined in code
- **Reproducible**: The same configuration produces the same result on
  any machine
- **Rollback**: Every configuration change creates a new "generation"
  you can switch back to
- **Isolated**: Packages are installed in the Nix store, not globally

Home-manager works on any Linux distribution - you don't need NixOS. You
just need the Nix package manager installed.

## What is sway-home?

[sway-home](https://github.com/EnigmaCurry/sway-home) is a home-manager
configuration that sets up a complete development environment. It
includes:

- Shell configuration (bash, with aliases and completions)
- Editor setup (Emacs)
- Development tools (git, ripgrep, just, etc.)
- Window manager config (Sway, if you're on Wayland)
- And relevantly: nixos-vm-template integration

When you activate sway-home with home-manager, you get all of this
configured and ready to use. The configuration is modular - you can
enable or disable components as needed.

## The hm-* commands

Sway-home provides shell aliases for common home-manager operations. These
are the commands you'll use to manage your environment:

| Command          | What it does                                                        |
|------------------|---------------------------------------------------------------------|
| `hm-switch`      | Rebuild and activate your home-manager configuration                |
| `hm-update`      | Update flake.lock to fetch latest versions of all inputs            |
| `hm-upgrade`     | Update + switch in one step                                         |
| `hm-generations` | List your configuration history (each activation is a "generation") |
| `hm-rollback`    | Revert to the previous generation if something breaks               |
| `hm-metadata`    | Show the git revisions of all flake inputs                          |
| `hm-pull`        | Git pull the sway-home repository                                   |

The typical workflow: edit your configuration, run `hm-switch` to apply
it. If you want the latest upstream changes from sway-home and its
dependencies (including nixos-vm-template), run `hm-upgrade`.

## The nixos-vm-template module

One of sway-home's modules, `nixos-vm-template.nix`, integrates the VM
tooling directly into your shell. It does three things:

1. Symlinks the nixos-vm-template repository into `~/nixos-vm-template`
   (bound to the nix store, so it's read-only but versioned)
2. Creates a default environment file at
   `~/.config/nixos-vm-template/env` with XDG-compliant paths
3. Sets up the `vm` shell alias with tab completion

After activating home-manager, you get a `vm` command that works like
this:

```bash
vm list                    # List all VMs
vm create myvm docker,dev  # Create a VM
vm start myvm              # Start it
vm ssh myvm                # SSH in
vm upgrade myvm            # Upgrade to new image
```

The `vm` command operates on the local machine's libvirt backend.

The alias is defined using the `_justfile_alias` function, which wraps
`just` with a specific Justfile and environment file:

```bash
_justfile_alias vm \
  "$HOME/nixos-vm-template/Justfile" \
  "$HOME/.config/nixos-vm-template/env"
```

This gives you full tab completion for recipes, machine names, and
profile names. Press Tab after `vm create myvm` and you'll see the
available profiles.

### The nix store binding

Here's an important detail: `~/nixos-vm-template` is a symlink into the
nix store, not a regular git clone. The module declares:

```nix
home.file."nixos-vm-template".source = inputs.nixos-vm-template;
```

This means the repository is read-only. You can't edit files there
directly. The benefit is reproducibility - your VM tooling version is
pinned to a specific commit in the sway-home flake.lock.

The downside is that changes to nixos-vm-template upstream won't appear
until you update and rebuild. More on that below.

### Where things live

The environment file sets up XDG-compliant paths:

| Path                                    | Purpose                                    |
|-----------------------------------------|--------------------------------------------|
| `~/.config/nixos-vm-template/machines/` | Machine configs (identity files, profiles) |
| `~/.config/nixos-vm-template/libvirt/`  | Libvirt XML templates                      |
| `~/.config/nixos-vm-template/env`       | Backend configuration                      |
| `~/.local/share/nixos-vm-template/`     | Built images and VM disks                  |

Your machine configs are in `~/.config`, so they're easy to back up and
track. The large image files go in `~/.local/share` where they won't
clutter your config backups.

## Updating nixos-vm-template

Since `~/nixos-vm-template` is bound to the nix store, you need to update
home-manager to get new versions:

```bash
hm-update    # Update flake.lock (fetches latest nixos-vm-template)
hm-switch    # Rebuild and activate
```

After this, `~/nixos-vm-template` points to the new version and all `vm`
commands use the updated code.

To see what version you're running:

```bash
hm-metadata
```

This shows the git revisions of all flake inputs, including
nixos-vm-template.

## Home-manager inside the VM

So far we've talked about home-manager on your **host workstation** -
managing your shell, your tools, and the nixos-vm-template integration.
But you can also run home-manager **inside the VM** to manage the user
environment there.

To get home-manager inside a VM, include the `home-manager` profile when
creating it:

```bash
vm create myvm dev,docker,home-manager 8192 4
```

The `home-manager` profile installs sway-home's configuration inside the
VM, giving you the same shell setup, editor config, and tools. This is
useful for development VMs where you want a consistent environment.

The profile works in both immutable and mutable VMs, but with slightly
different behavior:

- In **immutable VMs**, a custom activation service creates symlinks from
  `/home/<user>` to the nix store. This handles the complexity of the
  read-only root and bind-mounted home directories.

- In **mutable VMs**, standard home-manager activation runs. The
  filesystem is writable, so home-manager just does its normal thing.

Note that the `dev` profile includes basic development tools (neovim,
tmux, etc.) but does **not** include home-manager. If you want the full
sway-home experience inside the VM, add the `home-manager` profile
explicitly.

## Creating a Proxmox alias

The `vm` alias points at libvirt by default. If you also have a Proxmox
server, you can create a separate alias for it.

First, create an environment file for your Proxmox backend:

```bash
cat > ~/.config/nixos-vm-template/env-pve << 'EOF'
BACKEND=proxmox
PVE_HOST=pve
PVE_NODE=pve
PVE_STORAGE=local-zfs
PVE_DISK_FORMAT=raw
PVE_BRIDGE=vmbr0
OUTPUT_DIR=$HOME/.local/share/nixos-vm-template
MACHINES_DIR=$HOME/.config/nixos-vm-template/machines-pve
LIBVIRT_DIR=$HOME/.config/nixos-vm-template/libvirt
EOF
```

Note the separate `MACHINES_DIR` - this keeps Proxmox machine configs
separate from libvirt ones, avoiding confusion.

Then add the alias to your shell config (e.g., `~/.bashrc` or the
sway-home `config/bash/alias.sh`):

```bash
_justfile_alias pve \
  "$HOME/nixos-vm-template/Justfile" \
  "$HOME/.config/nixos-vm-template/env-pve"
```

Now you have two aliases:

```bash
vm create myvm docker      # Creates on local libvirt
pve create myvm docker     # Creates on Proxmox server
```

Both use the same nixos-vm-template codebase but target different
backends with different configurations.

## Disk space and garbage collection

VM images accumulate in `~/.local/share/nixos-vm-template/`. Each profile
combination produces an image (typically 3-4 GB), and each VM has its own
`/var` disk.

To see disk usage:

```bash
du -sh ~/.local/share/nixos-vm-template/
```

To clean up old images (keeping currently-used ones):

```bash
vm clean
```

For the nix store itself, home-manager profiles accumulate over time. To
reclaim space:

```bash
nix-collect-garbage --delete-older-than 30d
```

This removes store paths that aren't referenced by any generation newer
than 30 days. Be careful - this includes home-manager generations, so
you'll lose the ability to roll back to older configs.

To see how much space you'd reclaim:

```bash
nix-store --gc --print-dead
```

## The full workflow

Here's what a typical session looks like:

```bash
# Update everything
hm-pull && hm-upgrade

# Check what version of nixos-vm-template you're running
hm-metadata | grep nixos-vm-template

# Create a VM for a new project (with home-manager for full sway-home inside)
vm create project-foo claude,dev,docker,home-manager 8192 4

# Work on the project...
vm ssh user@project-foo
# ... do things ...

# Later, upgrade the VM to pick up profile changes
vm upgrade project-foo

# Deploy to production on Proxmox
pve create project-foo docker
pve start project-foo

# Clean up old images
vm clean
nix-collect-garbage --delete-older-than 7d
```

## Conclusion

The sway-home integration turns nixos-vm-template into a first-class shell
tool. The `vm` alias gives you quick access to all VM operations with tab
completion, and the home-manager binding ensures reproducible tooling
versions across machines. Adding backend-specific aliases like `pve` lets
you manage VMs across multiple hypervisors from a single workflow.

The key things to remember:
- `~/nixos-vm-template` is read-only; run `hm-upgrade` to get updates
- Machine configs live in `~/.config/nixos-vm-template/machines/`
- Use `nix-collect-garbage` periodically to reclaim disk space
- Create separate aliases and machine directories for each backend

