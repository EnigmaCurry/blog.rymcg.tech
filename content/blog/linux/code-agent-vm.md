---
title: "NixOS VMs part 1: Running code agents in an immutable NixOS VM"
date: 2026-01-22T13:54:00-06:00
tags: ['linux', 'nixos', 'libvirt', 'nixos-vm-template']
---

*This is part 1 of a series on [nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template):*
1. *Running code agents in an immutable NixOS VM (this post)*
2. *[Bootstrapping a Docker server with immutable NixOS on Proxmox](/blog/linux/nixos-proxmox-vm/)*
3. *[Mutable VMs are cool too](/blog/linux/mutable-vms/)*
4. *[Managing VMs with home-manager and sway-home](/blog/linux/nixos-vm-home-manager/)*

---

AI coding agents like [Claude
Code](https://docs.anthropic.com/en/docs/claude-code) and [Open
Code](https://github.com/sst/opencode) run in your terminal, read and
write files, execute commands, and generally do whatever you tell them
to. Claude Code is Anthropic's official CLI agent; Open Code is an
open-source alternative that supports multiple model providers
(including Anthropic). Both are powerful, and both have full shell
access to whatever machine they're running on — which is a bit
concerning if that machine is your daily driver laptop.

This post walks through setting up a code agent inside an immutable
NixOS VM on a Fedora host, editing files remotely with Emacs TRAMP,
and using git branches so that the agent's work is immediately
testable on other machines.

## Why bother with a VM?

A code agent has shell access to whatever machine it's running on. It
can modify files and run any program. If you point it at your laptop's
home directory and say "refactor this project," it will happily do so,
and if something goes wrong, it went wrong on *your* machine.

A VM gives the agent its own filesystem to work with. The
[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template)
project builds immutable NixOS images with a read-only root filesystem
and a separate data disk. If the environment gets weird, you can blow
it away and recreate it in two commands. Your laptop stays clean.

The tradeoff is that you're SSH'ing into a VM instead of running
locally. With TRAMP this is basically invisible to Emacs, so it hasn't
bothered me.

## Install the prerequisites

This example uses a Fedora laptop, but Debian, Arch, or pretty much
any other Linux distro with KVM support will work. The only software
dependencies you need are libvirt and the Nix package manager:

```bash
# Fedora
sudo dnf install nix just git libvirt qemu-kvm virt-manager guestfs-tools edk2-ovmf
sudo systemctl enable --now nix-daemon libvirtd
```

Enable Nix flakes for this user:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

## Clone and build

```bash
git clone https://github.com/EnigmaCurry/nixos-vm-template \
   ~/nixos-vm-template
cd ~/nixos-vm-template
```

The template ships with composable profiles that you combine as needed.
For a full development environment with a code agent, combine the
`claude` (or `open-code`) profile with `dev`, `docker`, and `podman`.
The agent itself gets installed via npm on first login. Pick the one
you want and create a VM:

```bash
# For Claude Code with full dev environment:
just create

# When prompted, enter the VM name (e.g., "claude-dev")
# Select profiles: claude, dev, docker, podman
# Configure memory (8192), CPUs (4), and other settings
```

The `just create` command runs an interactive configuration wizard
that guides you through all the options, then builds the image,
creates the VM, and starts it automatically. The root filesystem is
read-only (immutable), and all mutable state lives on a separate
`/var` disk. Home directories are bind-mounted from `/var/home`.

## First boot

The VM starts automatically after `just create` completes. Check its
status and connect:

```bash
just status claude-dev      # prints the IP address
just ssh claude-dev         # SSH into the VM with the 'user' account
```

On first login, the shell profile detects that the agent isn't
installed yet and runs the appropriate npm install automatically
(`@anthropic-ai/claude-code` or `opencode-ai`). Both agents need an
API key for your service of choice. Here's an example for Anthropic:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
source ~/.bashrc
```

The Open Code profile also creates a default config at
`~/.config/opencode/config.json` pointing at Claude Opus 4.5. You can
edit that file to switch models or providers.

Set your git user profile and preferences:

```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
git config --global init.defaultBranch master
```

## Create a project repository

Create a fresh repository on GitHub for the agent to work in. This
will be the project it has full control over, committing and pushing
on your behalf. Go to GitHub and create a new repository (public or
private, your choice), then come back here.

Next, generate an SSH key on the VM so it can push to that repo:

```bash
ssh-keygen -t ed25519 -C "claude-dev-vm" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Copy the public key and add it as a deploy key on the repository:

1. Go to your repository on GitHub.
2. Navigate to **Settings > Deploy keys > Add deploy key**.
3. Paste the public key, give it a name like "claude-dev VM", and check
   **Allow write access**.
4. Click **Add key**.

Deploy keys are scoped to a single repository, which is a good fit
here. The VM only needs push access to the project it's working on,
not your entire GitHub account. If the agent is working on multiple
repos, generate a separate key per repo.

Verify the key works:

```bash
ssh -T git@github.com
```

You should see a message confirming authentication. Now clone the repo
on the VM:

```bash
cd ~
git clone git@github.com:you/your-project.git project
cd project
```

Run `claude` or `opencode` in the project directory.

## Editing files with TRAMP

TRAMP (Transparent Remote Access, Multiple Protocols) is Emacs's
built-in facility for editing remote files over SSH. You open a file
with a special path syntax and Emacs handles the rest, no FUSE mounts
or sync tools involved. 

You can read more about how to configure emacs [with my emacs
config](https://emacs.rymcg.tech).

(If you don't want to use Emacs, you can do something pretty similar
in VS Code with the [Remote Development
Extension](https://code.visualstudio.com/docs/remote/remote-overview)).

First, add an SSH config entry so you don't have to remember the IP:

```
# ~/.ssh/config
Host claude-dev
    HostName <ip>
    User user
    ControlMaster auto
    ControlPersist yes
    ControlPath /tmp/ssh-%u-%r@%h:%p
```

(The ControlMaster settings are optional, they enable SSH connection
sharing so you won't have to authenticate as often.)

Now you can open files on the VM directly:

```
C-x C-f /ssh:claude-dev:/home/user/project/src/main.rs
```

To get a shell running inside the VM, open a remote shell buffer:

```
M-x shell RET
```

When prompted for a directory, enter `/ssh:claude-dev:/home/user/`.
(Or use `vterm` if you prefer a proper terminal emulator in a buffer.)
Run your agent in that shell. Now you have it running in the VM, and
your Emacs buffers pointing at the same files it's modifying. When the
agent writes to a file you have open. In Emacs enable `M-x
auto-revert-mode` and the fill will automatically detect changes and
reload the file.

## SSH remote forwarding

Sometimes the agent needs access to a service running on your laptop.
For example, if you have a Traefik dashboard listening on
`127.0.0.1:8080`, you can expose it to the VM with SSH remote
forwarding:

```bash
ssh -R 8080:127.0.0.1:8080 user@claude-dev
```

This binds port 8080 on the VM to port 8080 on your laptop. Inside the
VM, the agent can now reach the Traefik dashboard at `127.0.0.1:8080`
as if it were local. You can add this to your SSH config to make it
persistent:

```
# ~/.ssh/config
Host claude-dev
    ...
    RemoteForward 8080 127.0.0.1:8080
```

This is useful for giving the agent access to local dev servers, API
endpoints, or dashboards without exposing them to your network.
Furthermore, the `claude` and `open-code` profiles explicitly block
access to [RFC 1918](https://www.rfc-editor.org/rfc/rfc1918) networks,
so if you need the agent to access some service on your LAN, this is
the only way.

## The git workflow

The real utility of this setup is the git branching workflow. You work
on a dev branch, the agent commits and pushes to it, and you can pull
those changes on any other machine to test.

### Setup

In the project you cloned earlier, check out a dev branch:

```bash
cd ~/project
git checkout -b dev/claude-work
```

### Agent directives

Both Claude Code and Open Code support project-level instruction
files. Claude Code reads `CLAUDE.md`; Open Code reads
`AGENTS.md`. Add one (or both) to the project root:

```markdown
- Always run `git pull` before making any changes.
- When working on a branch other than `master` or `main`, automatically commit
  and push changes when done with a task.
```

The agent reads this file and follows the directives. When you give it
a task ("add input validation to the login handler"), it will pull,
make the changes, commit with a message describing what it did, and
push.

### Testing on other machines

On your desktop, or wherever you want to test:

```bash
git fetch origin
git checkout dev/claude-work
git pull
# run tests, build, review the diff, whatever
```

If the tests fail, go back to the Emacs shell buffer and tell the
agent what went wrong. It pulls, fixes, commits, pushes. You pull
again. This loop works the same way it would with any remote
collaborator, except the collaborator happens to be an AI running in a
VM on your laptop.

When you're happy with the branch, merge it however you normally
merge branches.

## Snapshots

One of the nice things about running in a VM is that you can snapshot
the state disk before asking the agent to do anything particularly
adventurous:

```bash
just snapshot claude-dev before-refactor
```

If things go sideways:

```bash
just restore-snapshot claude-dev before-refactor
```

This only snapshots the `/var` disk (which contains home directories,
git repos, and all mutable state). The root filesystem is immutable so
there's nothing to snapshot there.

## Upgrades and profiles

The template uses composable mixin profiles. Instead of a deep
inheritance hierarchy, you combine profiles as needed:

```
core         → SSH daemon, user accounts, firewall (always included)
docker       → Docker daemon + user access
podman       → Podman + distrobox/buildah/skopeo
nvidia       → NVIDIA GPU support (requires docker)
python       → Python/uv development
rust         → Rust/rustup development
dev          → Development tools (neovim, tmux, etc.)
home-manager → Home-manager with sway-home modules (emacs, shell config, etc.)
claude       → Claude Code CLI
open-code    → OpenCode CLI
```

Profiles are specified as comma-separated lists. For example,
`claude,dev,docker,podman` gives you Claude Code with the full
development environment, Docker, and Podman. Each VM's selected
profiles are stored in `machines/<name>/profile`, which is set during
`just create` and read by `just upgrade` to know which image to
rebuild. To change a VM's profiles, edit that file and put the
comma-separated list you want, then run `just upgrade <name>`.

To add packages, edit the relevant profile file in `profiles/`, or
create your own. For example, to add `go` to the dev profile:

```nix
# profiles/dev.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    neovim
    tmux
    go  # add new packages here
  ];
}
```

After editing, rebuild and upgrade:

```bash
just upgrade claude-dev    # build and install new image, preserving /var
```

Your home directory, git repos, npm globals (including the agent
itself), and everything else on `/var` survives the upgrade. Only the
read-only root filesystem gets replaced.

## Multiple VMs

VMs created from the same base image are thin-provisioned (QCOW2
backing files), so they only store deltas from the shared image. You
can spin up multiple VMs — one per project or task — each with their
own repos and contexts, without duplicating the full OS image for each
one.

## Bridged networking

By default VMs use NAT, which means they're accessible from the host
but not from other machines on your LAN. If you want to pull the
agent's commits from a desktop on the same network without going
through GitHub, you can use bridged networking. When running `just
create`, select "bridge" for the network mode when prompted.

The VM will get an IP from your LAN's DHCP server and be directly
reachable from other machines.

See more information in the nixos-vm-template
[README.md](https://github.com/EnigmaCurry/nixos-vm-template?tab=readme-ov-file#bridged-networking)

## Conclusion

Putting a code agent in an immutable NixOS VM keeps your laptop safe:
the OS is read-only, mutable state is isolated on `/var`, and snapshots
make rollback trivial. With TRAMP and a branch-based git loop, it
still feels local—and the agent’s work is easy to test anywhere.
