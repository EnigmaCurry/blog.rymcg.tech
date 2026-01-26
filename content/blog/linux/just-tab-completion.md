---
title: "Enhanced tab completion for Justfiles with bash aliases"
date: 2026-01-25T12:00:00-06:00
tags: ['linux', 'bash', 'just']
---

[Just](https://github.com/casey/just) is a command runner - a modern
take on the Makefile. You define recipes in a `Justfile` and run them
with `just <recipe>`. It's become my go-to for project automation:
building code, managing VMs, running tests, whatever the project
needs.

Just has built-in tab completion for recipe names, which is nice. But it
stops there. If a recipe takes arguments, you're on your own. For a
project like
[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template),
where recipes like `create` take five or six arguments with valid values
that depend on the project state (profile names, existing VM names,
network modes), I wanted real completion for those arguments too.

This post covers a bash completion script that:

- Creates aliases that run a Justfile from any directory
- Provides tab completion for recipe arguments, not just recipe names
- Shows hints about the next expected argument and its default value
- Uses a naming convention in the Justfile to define valid completions

## The problem

Consider the `create` recipe from nixos-vm-template:

```just
# Justfile

create new_name profile="core" memory="2048" vcpus="2" var_size="30G" network="nat":
    @source {{backend_script}} && create_vm "{{new_name}}" ...
```

When you type `just create dev-01 ` and hit tab, nothing happens. Just
knows about recipe names, but it doesn't know that the second argument
is called `profile` or that valid profiles are `core`, `docker`,
`claude`, etc.

I wanted this:

```
$ mrfusion-proxmox create dev
Next arg: profile (default "core")

base        claude      core        dev         docker      docker-dev  open-code   python      rust        ssh
```

## The solution: a completion convention

The approach has two parts:

1. **A bash script** that parses Justfile recipe signatures to understand
   argument positions and names.

2. **A naming convention** in the Justfile: for any argument named `foo`,
   a hidden recipe `_completion_foo` outputs valid values.

Here's the convention in the Justfile:

```just
# Justfile

# The main recipe with arguments
create new_name profile="core" memory="2048" vcpus="2" var_size="30G" network="nat":
    @source {{backend_script}} && create_vm ...

# Completion providers - one per argument type
_completion_profile:
    @shopt -s nullglob; for f in profiles/*.nix; do basename "$f" .nix; done

_completion_network:
    @printf "nat\nbridge\n"

_completion_name:
    @shopt -s nullglob; for f in machines/*; do basename $f; done
```

The completion script sees that you're on argument index 1 of `create`,
looks up the signature to find that argument is named `profile`, then
runs `just _completion_profile` to get the valid values.

## Setting up the alias

Source the completion script in your `.bashrc`:

```bash
source ~/path/to/just-completion.sh
```

Then define an alias with `_justfile_alias`:

```bash
_justfile_alias mrfusion-proxmox \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/Justfile" \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/.env-mrfusion"
```

The function takes three arguments:

- **Alias name** - what you'll type to run the recipes
- **Justfile path** - the full path to the Justfile
- **Dotenv file** (optional) - an environment file to load with `-E`

Now `mrfusion-proxmox` is a command you can run from anywhere. It wraps
`just -f <justfile> -d <workdir> -E <dotenv>` and provides full tab
completion.

## How it works

When you type `mrfusion-proxmox ` and hit tab, you get recipe names
(delegated to just's built-in completion).

When you type `mrfusion-proxmox create dev-01 ` and hit tab:

1. The script sees you're completing argument index 1 (0-indexed) of the
   `create` recipe.

2. It runs `just --show create` to get the recipe signature:
   ```
   create new_name profile="core" memory="2048" vcpus="2" var_size="30G" network="nat":
   ```

3. It parses this to find that argument index 1 is `profile="core"`.

4. It extracts the parameter name `profile` and runs
   `just _completion_profile` to get candidates.

5. If your cursor is on an empty token, it also prints a hint:
   ```
   Next arg: profile (default "core")
   ```

6. The candidates (`base`, `claude`, `core`, etc.) populate the
   completion list.

For arguments without a `_completion_<name>` recipe, you still get the
hint showing the argument name and default value - you just don't get
completion candidates.

## The completion script

Here's the core of the alias completion function:

```bash
_justfile_alias_complete() {
  local alias_name="${COMP_WORDS[0]}"
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local recipe="${COMP_WORDS[1]}"

  # If completing recipe name or flags, delegate to just's stock completion.
  if (( COMP_CWORD <= 1 )) || [[ "$cur" == -* ]]; then
    JUST_JUSTFILE="$justfile" JUST_WORKING_DIRECTORY="$workdir" _just "$alias_name"
    return 0
  fi

  # We are completing a positional arg
  local arg_index=$((COMP_CWORD - 2))

  # Get the param name at this position from the recipe signature
  local tok name
  tok="$(_justfile_alias_param_token "$alias_name" "$recipe" "$arg_index")"
  name="${tok%%=*}"

  # Try `_completion_<name>` for candidates
  if [[ -n "$name" ]]; then
    local -a cands
    mapfile -t cands < <(_justfile_alias_param_candidates "$alias_name" "$name")

    if (( ${#cands[@]} > 0 )); then
      [[ -z "$cur" ]] && _justfile_alias_next_arg_hint "$alias_name" "$recipe" "$arg_index"
      COMPREPLY=($(compgen -W "${cands[*]}" -- "$cur"))
      return 0
    fi
  fi

  # No candidates: show hint when cur is empty
  if [[ -z "$cur" ]]; then
    _justfile_alias_next_arg_hint "$alias_name" "$recipe" "$arg_index"
    COMPREPLY=()
    return 0
  fi
}
```

The hint printing uses ANSI escapes to show the hint without garbling
the current input line:

```bash
_justfile_alias_hint() {
  printf '\e7' >&2        # save cursor
  printf '\e[J' >&2       # clear to end of screen
  printf '\n\e[2K%s\n' "$1" >&2
  printf '\e8' >&2        # restore cursor
}
```

## Real-world example: nixos-vm-template

Here's my actual setup for managing VMs on two Proxmox clusters with
different configurations:

```bash
# ~/.bashrc
source ~/git/vendor/enigmacurry/sway-home/config/bash/just-completion.sh

# MrFusion Proxmox cluster
_justfile_alias mrfusion-proxmox \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/Justfile" \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/.env-mrfusion"

# Flux Libvirt manager
_justfile_alias flux-libvirt \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/Justfile" \
  "$HOME/git/vendor/enigmacurry/nixos-vm-template/.env-libvirt"
```

Each `.env` file points to a different Proxmox host:

```bash
# .env-mrfusion
BACKEND=proxmox
PVE_HOST=192.168.1.100
PVE_NODE=mrfusion
PVE_STORAGE=local-zfs
PVE_BRIDGE=vmbr0
```

Now I can manage VMs on either cluster from any directory:

```
$ mrfusion-proxmox status
Next arg: name (required)

apps01      claude-dev  docker-test

$ mrfusion-proxmox status apps01
Name: apps01
State: running
IP: 192.168.1.42
```

The completions pull from the actual machine configs on disk, so they're
always up to date.

## Adding completions to your own Justfile

To add argument completion to your recipes:

1. Identify which arguments have a known set of valid values.

2. Add a hidden recipe for each, following the `_completion_<param>`
   naming convention:

```just
# Your recipe
deploy env="staging" service="api":
    ./deploy.sh {{env}} {{service}}

# Completion providers
_completion_env:
    @printf "dev\nstaging\nprod\n"

_completion_service:
    @ls services/
```

The completion recipe can be any command that outputs one value per
line. It runs in the Justfile's working directory, so it can inspect
project state.

## Gotchas

A few things to watch out for:

- **Argument order matters.** The script uses positional indexing. If
  your recipe is `foo a b c:`, the first argument after `foo` is `a`,
  the second is `b`, etc. Named arguments (`foo a=1 b=2:`) still work
  positionally.

- **Spaces in values** are not handled. If your completion values have
  spaces, you'll need to quote them on the command line.

- **Performance.** Each completion invokes `just --show <recipe>` to
  parse the signature. This is fast enough for interactive use, but
  you might notice a slight delay on very large Justfiles.

## The full script

The complete script is available in my dotfiles:
[just-completion.sh](https://github.com/EnigmaCurry/sway-home/blob/master/config/bash/just-completion.sh)

## Wrapping up

This setup has made working with nixos-vm-template much smoother. I can
manage VMs across multiple Proxmox clusters from any terminal, with full
tab completion for profiles, VM names, and network modes. The same
pattern works for any Justfile with discoverable argument values.

The key insight is that the Justfile itself can provide completion
candidates through hidden recipes. The bash completion script just needs
to know where to look.
