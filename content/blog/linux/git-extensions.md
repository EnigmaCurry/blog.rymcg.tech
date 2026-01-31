---
title: "Extensions to git"
date: 2026-01-31T00:00:00-06:00
tags: ['linux', 'git']
---

Git is already a mass of arcane incantations and eldritch commands. So
naturally, we're going to bolt more onto it. Why? Because typing the
same 47-character SSH URL for the hundredth time is a rite of passage
nobody asked for.

This post introduces a script that adds several custom git
subcommands, turning your terminal into an even more dangerous weapon
of mass productivity.

## How git extensions work

Here's a dirty little secret: git will run any executable named
`git-<something>` that's in your `PATH` as if it were a built-in
subcommand. Drop a script called `git-hierarchicaldiffvisualization`
somewhere in your path, and suddenly `git
hierarchicaldiffvisualization` is a real command that your coworkers
will hate you for.

We exploit this "feature" by creating a single script
(`git_extensions.sh`) and symlinking it multiple times with different
names:

```bash
ln -s /path/to/git_extensions.sh ~/.local/bin/git-vendor
ln -s /path/to/git_extensions.sh ~/.local/bin/git-deploy
ln -s /path/to/git_extensions.sh ~/.local/bin/git-deploy-key
ln -s /path/to/git_extensions.sh ~/.local/bin/git-remote-proto
```

The script detects which name it was invoked as and dispatches to the
appropriate handler. A monolithic git extension toolkit.

## git vendor

Tired of your `~/Downloads` folder looking like a git graveyard? `git
vendor` clones repositories to a consistent location:
`~/git/vendor/{org}/{repo}`.

The killer feature is flexible input parsing. All of these work:

```bash
git vendor enigmacurry/sway-home
git vendor github.com/torvalds/linux
git vendor https://github.com/EnigmaCurry/blog.rymcg.tech.git
git vendor git@github.com:EnigmaCurry/sway-home.git
git vendor ssh://git@forgejo.example.com:2222/EnigmaCurry/emacs.git
```

The org name gets lowercased for filesystem consistency, because we're
civilized people who don't want `EnigmaCurry/` and `enigmacurry/`
fighting for dominance.

If the repository already exists, it just tells you where it is and
exits-no redundant clones, no drama.

## git deploy

Sometimes you need to clone a repository on a server using a
*deploy key*-a dedicated SSH key that grants access to a single repo.
This is common for CI/CD pipelines, automated deployments, or any
situation where you don't want your personal keys floating around.

`git deploy` automates the tedious dance:

```bash
git deploy git@github.com:EnigmaCurry/secret-project.git
```

On first run, it:

1. Generates an ed25519 SSH key in `~/.ssh/deploy-keys/`
2. Adds an SSH host alias to `~/.ssh/config`
3. Shows you the public key to add to your git server
4. Exits with an error (because the key isn't authorized yet)

After you add the key to GitHub/GitLab/Forgejo, run the same command
again. This time it succeeds and clones the repository.

You can also convert an existing repository to use a deploy key:

```bash
cd /path/to/existing/repo
git deploy .
```

The default clone destination follows the same pattern as `git
vendor`: `~/git/vendor/{org}/{repo}`.

## git deploy-key

Manage your deploy keys without spelunking through `~/.ssh/`:

```bash
# List all deploy keys
git deploy-key list

# Show a key's public key (for re-adding to git servers)
git deploy-key show deploy--github.com--enigmacurry-project

# Remove a deploy key and its SSH config entry
git deploy-key remove deploy--github.com--enigmacurry-project
```

## git remote-proto

Switch your remote URL between protocols without manually editing
anything:

```bash
# You cloned with HTTPS like a normal person
git remote -v
# origin  https://github.com/enigmacurry/kick-ascii (fetch)

# But now you want SSH
git remote-proto git

# Current: https://github.com/enigmacurry/kick-ascii
# Updated: git@github.com:enigmacurry/kick-ascii.git
```

Supported protocols:

| Protocol         | URL Format                          |
|------------------|-------------------------------------|
| `http` / `https` | `https://{host}/{org}/{repo}.git`   |
| `git`            | `git@{host}:{org}/{repo}.git`       |
| `ssh`            | `ssh://git@{host}/{org}/{repo}.git` |

For SSH with a custom port:

```bash
git remote-proto ssh --port 2222
# Updated: ssh://git@github.com:2222/enigmacurry/kick-ascii.git
```

## Installation

It is already installed if you use my
[sway-home](https://github.com/EnigmaCurry/sway-home) config. But
assuming you don't, here's how to install it by hand:

```bash
## Download the script and make it executable:
curl -Lo ~/.local/bin/git_extensions.sh \
  https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/git/git_extensions.sh
chmod +x ~/.local/bin/git_extensions.sh

## Create symlinks for each extension:
ln -s git_extensions.sh ~/.local/bin/git-vendor
ln -s git_extensions.sh ~/.local/bin/git-deploy
ln -s git_extensions.sh ~/.local/bin/git-deploy-key
ln -s git_extensions.sh ~/.local/bin/git-remote-proto
```

Verify: `git vendor --help`

Now go forth and clone responsibly.

## See Also

Projects that are similar to this one:

 * [ghq](https://github.com/x-motemen/ghq)
 * [git-extras](https://github.com/tj/git-extras)

## The script

 * [Download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/git/git_extensions.sh)

{{< code file="/src/git/git_extensions.sh" language="shell" >}}
