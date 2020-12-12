---
title: "K3s part 1: Setup your workstation"
date: 2020-12-11T00:01:00-06:00
tags: ['k3s']
---

## Prepare your workstation

When working with kubernetes, you should eschew directly logging into the host
server via SSH, unless you have to. Instead, we will create all files and do all
of the setup, indirectly, from your local laptop, which will be referred to as
your workstation. `kubectl` is your local workstation tool to access the remote
cluster API.

You will need:

 * A modern BASH shell, being the default Linux terminal shell.
 * `kubectl` on your workstation:
 
   * Prefer your os packages:
   
     * Arch Linux: `sudo pacman -S kubectl`
     * Other OS: [See docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-using-native-package-management)
     
     * You can take a small detour now and setup bash shell completion for
       kubectl, this is quite useful. Run `kubectl completion -h` and follow the
       directions for setting up your shell. However, you can skip this, it's
       not required.
       
 * `kustomize` on your workstation:
 
   * Prefer your os packages:
   
     * Arch Linux: `sudo pacman -S kustomize`
     * Other OS: [see releases](https://github.com/kubernetes-sigs/kustomize/releases)
   * You may know about kubectl having kustomize builtin (`kubectl apply -k`).
     However, the version of kustomize that is bundled with kubectl is old, and
     has bugs. You should use the latest version of `kustomize` directly instead
     of the bundled kubectl version (`kustomize build | kubectl apply -f - `).

 * `git` on your workstation:
 
   * Prefer your os packages:
   
     * Arch Linux: `sudo pacman -S git`
     * Ubuntu: `sudo apt install git`
     
## Running Commands

This blog is written in a Literate Programming style, containing *exact* BASH
shell commands for you to paste into your workstation terminal.

These block-quoted commands are intended to be copy-and-pasted directly into
your terminal *without editing them*. Commands that need configuration, will
reference environment variables, which you create before you run the command, so
that you may customize the variables first, and then run the command as-is.

You should configure your BASH so that your pasted commands are never run
without your confirmation, after pasting, by pressing Enter. This also allows
you the opportunity to edit the commands on the terminal prompt line, (which you
will only need to do in the case of customizing variables, not for editing
commands). Run this to enable this feature in BASH:

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

Often, a command will use the [BASH HEREDOC
format](https://tldp.org/LDP/abs/html/here-docs.html) to create whole files
without needing to use a text editor. For example, this next code block will
create a new temporary file with a random name, with the contents `Hello,
World!`. 

```bash
TMP_FILE=$(mktemp)
cat <<EOF > ${TMP_FILE}
Hello, World!
EOF

echo "-------------------------------------------"
echo The random temporary file is ${TMP_FILE}
echo The contents written were: $(cat ${TMP_FILE})
```
The contents of the file is the lines between `cat <<EOF` and the last
`EOF` (highlighted in yellow on this blog). Any command that comes after the
`EOF` is just a regular command, not part of the content of the file created.
(Technically, HEREDOC format allows any marker instead of `EOF` but this blog
will always use `EOF` by convention, which is mnemonic for `End Of File`.)

Note that previous example rendered environment variables *before* writing the
file. The file contains the *value* of the variable at the time of creation, not
the variable name reference itself. In order to write a shell script via
HEREDOC, that contains variable name references, you need to disable this
behaviour. To do this, you put single quotes around the `EOF` marker:

```bash
TMP_FILE=$(mktemp --suffix .sh)
cat <<'EOF' > ${TMP_FILE}
## I'm a shell script that needs raw variable names to be preserved
## To do this, the HEREDOC used <<'EOF' instead of <<EOF
echo Hello I am $(whoami) on $(hostname)
EOF

echo "-------------------------------------------"
cat ${TMP_FILE}
echo "The variables are evaluated on run:"
sh ${TMP_FILE}
```

## Create a local git repository

You need a place to store your cluster configuration, so create a git repository
someplace on your workstation called `flux-infra` (or whatever you want to call
it). The `flux-infra` repository will manage the root level of one or more of
your clusters. Each cluster storing its manifests in its own sub-directory,
listed by domain name. Each kubernetes namespace gets a sub-sub-directory :
 * `~/git/flux-infra/${CLUSTER}/${NAMESPACE}` 
 
Choose the directory where to create the git repo and the domain name for your
new cluster:

```env
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=flux.example.com
```

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER} && \
git -C ${FLUX_INFRA_DIR} init && \
cd ${FLUX_INFRA_DIR}/${CLUSTER} && \
echo Cluster working directory: $(pwd)
```
