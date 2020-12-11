---
title: "K3s part 1: Setup your workstation"
date: 2020-12-11T00:01:00-06:00
tags: ['k3s']
draft: true
---

## Prepare your workstation

When working with kubernetes, you should eschew directly logging into the host
server via SSH, unless you have to. Instead, we will create all files and do all
of the setup, indirectly, from your local laptop, which will be referred to as
your workstation. `kubectl` is our local workstation tool to access the remote
cluster.

 * Install kubectl on your workstation:
 
   * Prefer your os packages:
   
     * Arch Linux: `sudo pacman -S kubectl`
     
     * Ubuntu and Other OS: [See docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-using-native-package-management)
     
     * You can take a small detour now and setup bash shell completion for
       kubectl, this is quite useful. Run `kubectl completion -h` and follow the
       directions for setting up your shell. However, you can skip this, it's
       not required.
       
 * Install kustomize on your workstation:
 
   * Prefer your os packages:
   
     * Arch Linux: `sudo pacman -S kustomize`
     * Ubuntu and Other OS: [see releases](https://github.com/kubernetes-sigs/kustomize/releases)
   * You may know about kubectl having kustomize builtin (`kubectl apply -k`).
     However, the version of kustomize that is bundled with kubectl is old, and
     has bugs. You should use the latest version of `kustomize` directly instead
     of the bundled kubectl version (`kustomize build | kubectl apply -f - `).

## Running Commands

This blog is written in a Literate Programming style, containing BASH shell
commands to paste into your terminal.

These block-quoted commands are intended to be copy-and-pasted directly into
your terminal without editing them. Commands that need configuration, will
reference environment variables, which you create before you run the command, so
that you may customize the variables first, and then run the command as-is.

You should configure BASH so that your pasted commands are never run without
your confirmation, by pressing Enter. This also allows you the chance to edit
the commands, which you will only need to do in the case of editing environment
variables. Run this to enable this feature in BASH:

```bash
# Enable for the current shell:
bind 'set enable-bracketed-paste on'
# Enable for future environments:
echo "set enable-bracketed-paste on" >> ${HOME}/.inputrc
```

For example, here is a command block that is asking you to customize two
environment variables (`SOME_VARIABLE` and `SOME_OTHER_VARIABLE`). You should
copy and paste this into your shell, and edit the values in the command (`foo`
and `bar`) to something else, then Press Enter.

```env
SOME_VARIABLE=foo
SOME_OTHER_VARIABLE=bar
```

Now run a command that references the variables. You don't need to edit it, just
copy the command, paste into the terminal, and press Enter:

```bash
echo some command that needs ${SOME_VARIABLE} and ${SOME_OTHER_VARIABLE}
```


## Create a git repository

