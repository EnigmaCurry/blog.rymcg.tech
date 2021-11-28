---
title: "K3s part 1: Setup your workstation"
date: 2020-12-11T00:01:00-06:00
tags: ['k3s']
---

This is the first post in the K3s series, [read the introduction
first](/tags/k3s).

## Prepare your workstation

When working with kubernetes, you should resist the urge to directly login into
the host server via SSH, unless you have to. Instead, you will create all of the
config files on your local laptop, which will be referred to as your
workstation, and use `kubectl` to access the remote cluster API.

You will need to install several command line tools on your workstation (or
follow the guide to [build a utility
container](#create-toolbox-container-optional) to use as your virtual
"workstation" environment, which has all of the tools builtin):

 * A modern BASH shell, being the default Linux terminal shell, but also
   available on various platforms.
 * `kubectl`:
   * Arch Linux: `sudo pacman -S kubectl`
   * Other OS: [See docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-using-native-package-management)
   * You can take a small detour now and setup bash shell tab-key completion for
     kubectl, this is quite useful for interactive use. Run `kubectl completion
     -h` and follow the directions for setting up your shell. However, you can
     skip this, since all of the commands you will run are already prepared for
     you in this blog.
       
 * `kustomize`:
   * Arch Linux: `sudo pacman -S kustomize`
   * Other OS: [see releases](https://github.com/kubernetes-sigs/kustomize/releases)
   * You may have heard about kubectl having kustomize as a built-in feature
     (`kubectl apply -k`). However, the version of kustomize that is bundled
     with kubectl is old, and has bugs. You should use the latest version of
     `kustomize` directly instead of the bundled kubectl version (`kustomize
     build | kubectl apply -f - `).
   * NOTICE: [kustomize v3.9.0 does not
     work](https://github.com/kubernetes-sigs/kustomize/issues/3340#issue-761638279)
     (Fails to create `RoleBinding` resources) This may already be fixed in a
     later version, but the tested WORKING version as of 2020-12-14 is kustomize
     [v3.8.8](https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv3.8.8)
     
 * `kubeseal`:
 
   * Arch Linux has an [AUR build](https://aur.archlinux.org/packages/kubeseal/)
   * Other OS: [see releases](https://github.com/bitnami-labs/sealed-secrets/releases)
   * Note: only install the client side at this point, you will install the
     cluster side later in a different way.

 * `flux`:
 
   * Arch Linux has an [AUR build](https://aur.archlinux.org/packages/flux-go/)
   * Other OS: [see docs](https://github.com/fluxcd/flux2/tree/main/install)
   * Optional: Add shell completion support to your `~/.bashrc`
   
```env-static
## Optional bash shell completion for flux
. <(flux completion bash)
```

 * `git`:
   * Arch Linux: `sudo pacman -S git`
   * Ubuntu: `sudo apt install git`
   * [Other OS](https://git-scm.com/downloads)

 * `tea`:
   * Gitea command line client, useful for creating remote git repos
   * [Install docs](https://gitea.com/gitea/tea)

 * `jq` and `yq`:
   * JSON and YAML wrangling tools.
   * Arch Linux: `sudo pacman -S jq yq`
   * Ubuntu: `sudo apt install jq yq`
   
 * `podman` and `docker`:
   * Sometimes it is useful to run a container on your local workstation, podman
     can run rootless (no sudo required), and is the best option for doing this.
   * This won't be used until [part 7](/blog/k3s/k3s-07-mutual-tls)
   * This is also useful for [installing all of these tools in a
     container](#create-toolbox-container-optional) rather than native on your
     workstation.
   * [Install Podman](https://podman.io/getting-started/installation).
   * The Docker CLI client is still useful for interfacing with remote docker
     servers (or Virtual Machine).
   * [Install Docker](https://docs.docker.com/engine/install/) (you only need
     the client, not the engine, but this [and most distros] package both parts
     in the same package. You do not need to start the docker service, you will
     only use the docker client.)
   * DO NOT follow common advice to `alias docker=podman`. Podman and Docker are
     useful for different purposes, and you should install both. Podman doesn't
     have a daemon, and it can't talk to one; this is convenient, and secure,
     for running containers locally on your workstation with your normal user
     account (rootless). Docker (the CLI client) is useful for controlling
     *remote* Docker servers (or VM) by setting `DOCKER_HOST`. Podman can also
     act as a client for remote *podman* hosts (through socket activation) but
     it can't talk to a Docker daemon (local nor remote). Docker (the engine)
     requires running a daemon, which is normally run as root (or another
     priviliged account), and so is mostly unusable for rootless accounts, but
     this can be made to work well with a Virtual Machine (normal user runs
     docker client running on workstation, controlling docker daemon installed
     inside VM.)
     
 * `vagrant` (Optional):
   * A Virtual Machine manager
   * Only used for [Part 12](/blog/k3s/k3s-12-drone-development), for installing
     a Virtual Machine to run Docker (daemon) and a Drone runner, running CI
     jobs for your remote cluster, but on your local workstation.
   * [Arch Linux](https://wiki.archlinux.org/index.php/Vagrant#Installation)
   * Also install
     [libvirt](https://wiki.archlinux.org/index.php/Libvirt#Installation)
   * Install the libvirt plugin too: `vagrant plugin install vagrant-libvirt`

 * `hugo` (Optional) :
   * To build [the source code](https://github.com/EnigmaCurry/blog.rymcg.tech)
     and serve this blog from localhost (Or just continue reading this blog
     online.)
   * Arch Linux: `sudo pacman -S hugo`
   * [Other OS](https://gohugo.io/getting-started/installing/)
   
 * `k3sup` (Optional) :
   * [alexellis/k3sup](https://github.com/alexellis/k3sup) is a very useful tool
     to automatically create k3s clusters on machines that you already have SSH
     access to.
   * [Releases](https://github.com/alexellis/k3sup/releases)
   
 * `CDK8s` (Optional) :
   * Programmatically generate YAML from python, typescript, or java.
   * [Install CDK8s](https://cdk8s.io/docs/latest/getting-started/)
   
 * `OpenFaaS` (Optional) :
   * Create serverless functions and microservices
   * [Install OpenFaaS CLI](https://docs.openfaas.com/cli/install/)
   
## Running Commands

This blog is written in a Literate Programming style, containing *exact* BASH
shell commands for you to copy and paste into your workstation terminal.

These block-quoted commands are intended to be run *without needing to edit
them*. Commands that need configuration, will reference environment variables,
which you create before you run the command, so that you may customize the
variables first, and then run the command as-is.

You should configure your BASH so that your pasted commands are never run unless
you give your confirmation, after pasting, by pressing the Enter key. In
general, this allows you the opportunity to edit commands on the terminal prompt
line, before running them. (In this case, you will only need to do this in the
case of customizing variables, not for editing commands, which should be run
without editing them.) Run this to enable this feature, called
`bracketed-paste`, in BASH:

```bash
# Enable for the current shell:
bind 'set enable-bracketed-paste on'
# Enable for future environments:
echo "set enable-bracketed-paste on" >> ${HOME}/.inputrc
```

For example, here is a command block that is asking you to customize two
environment variables (`SOME_VARIABLE` and `SOME_OTHER_VARIABLE`). You should
copy and paste this into your shell, and edit the values on the command line
(`foo` and `bar`; change them to something else), then press Enter.

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

The contents of the file is the line(s) between `cat <<EOF` on line 2 and the
second `EOF` on its own line, line 4 (`Hello, World!\n`). Any lines that comes
after the second `EOF` (the `echo` lines) are just regular commands, not part of
the content of the file created. (Technically, HEREDOC format allows any marker
instead of `EOF` but this blog will always use `EOF` by convention, which is
mnemonic for `End Of File`.)

Note that the previous example rendered environment variables *before* writing
the file. The file contains the *value* of the variable as it was at the time of
creation, and replaces the variable name reference. In order to write a shell
script, via HEREDOC, that contains variable *names* (not values), you need to
disable this behaviour. To do this, you put quotes around the first `EOF`
marker, and then no variables will be substituted in the body:

```bash
TMP_FILE=$(mktemp --suffix .sh)
cat <<'EOF' > ${TMP_FILE}
## I'm a shell script that needs raw variable names to be preserved.
## To do this, the HEREDOC used <<'EOF' instead of <<EOF
echo Hello I am ${USER} on ${HOSTNAME} at $(date)
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
CLUSTER=k3s.example.com
```

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER} && \
git -C ${FLUX_INFRA_DIR} init && \
cd ${FLUX_INFRA_DIR}/${CLUSTER} && \
echo Cluster working directory: $(pwd)
```

In an upcoming post, you will create a git remote to push this repository to.

## Create toolbox container (optional)

As an alternative to installing all of these command line tools natively on your
workstation, you can build a utility container that has all of the tools inside.
If you go this route, the utility container becomes your "workstation", and
whenever this blog tells you to run something on your "workstation", it will
mean for you to run it inside this container instead. 

If you skipped down to this section, it is critical to go back up and read the
section titled [Running Commands](#running-commands) once you get your utility
container up and going.

This container will create a persistent volume mounted to the virtual home
directory (`/root` inside the container), for keeping files safe. Git
repositories are intended to be cloned somewhere in your native workstation home
directory, and then mounted inside the container (eg. a host directory
`${HOME}/git` mounted as `/root/git` inside the container). This way you can
still use your native workstation editor tools, rather than installing an editor
in the container.

This requires you to [install
podman](https://podman.io/getting-started/installation).

Build the container image (`kube-toolbox`):

```bash
cat <<'EOF' | podman build -t kube-toolbox -f - 
FROM alpine:latest

ARG GIT_TEA_VERSION=0.6.0
ARG KUSTOMIZE_VERSION=v3.9.1
ARG PODMAN_REMOTE_VERSION=v2.2.1

## Packages and upstream Kubernetes tools:
RUN cd /usr/local/bin && \
 apk add --no-cache bash curl openssh git bash-completion jq docker-cli && \
 echo "## Arkade installer" && \
   curl -sLS https://dl.get-arkade.dev | sh && \
   arkade get kubectl && \
   arkade get kubeseal && \
   arkade get hugo && \
   arkade get k3sup && \
   arkade get faas-cli && \
   arkade get helm && \
   arkade get k9s && \
   mv /root/.arkade/bin/* /usr/local/bin && \
 echo "### Kustomize (direct URL because arkade is broken see #299): " && \
   curl -LO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
   tar xfvz kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
   rm kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
 echo "### Flux: " && \
   curl -sL https://toolkit.fluxcd.io/install.sh | bash && \
 echo "### cdk8s / pyenv" && \
   apk add libffi-dev openssl-dev bzip2-dev zlib-dev readline-dev \
      sqlite-dev build-base python3 py3-pip yarn npm && \
   pip install --user pipenv && \
   curl https://pyenv.run | bash && \
   yarn global add cdk8s-cli && \
 echo "### Podman remote" && \
   curl -LO https://github.com/containers/podman/releases/download/${PODMAN_REMOTE_VERSION}/podman-remote-static.tar.gz && \
   tar xfvz podman-remote-static.tar.gz && \
   rm podman-remote-static.tar.gz && \
   mv podman-remote-static podman && \
 echo "## yq" && \
   pip install yq && \
 echo "## git-tea" && \
   curl -LO \
     https://dl.gitea.io/tea/${GIT_TEA_VERSION}/tea-${GIT_TEA_VERSION}-linux-amd64 && \
   mv tea-${GIT_TEA_VERSION}-linux-amd64 tea && \
   chmod 0755 tea
   
WORKDIR /root

## root account setup:
## Note that the files in the /root volume will override these image defaults:
RUN echo 'export PATH=${HOME}/.arkade/bin:${HOME}/.local/bin:${PATH}' >> .bashrc && \
    echo 'source /usr/share/bash-completion/bash_completion' >> .bashrc && \
    echo 'source <(kubectl completion bash)' >> .bashrc && \
    echo 'source <(flux completion bash)' >> .bashrc && \
    echo 'export PS1="[\u@kube-toolbox \W]\$ "' >> .bashrc && \
    echo 'set enable-bracketed-paste on' > .inputrc

CMD /bin/bash
EOF
```

Create an alias `kbox` to easily start the container shell:

```env-static
## You can create multiple aliases for different environments
## Just make sure to use a different volume name for each one (eg. kbox:/root)
alias kbox="podman run --rm -it -v kbox:/root -v ${HOME}/git:/root/git \
   -v ${HOME}/.gitconfig:/root/.gitconfig --name kbox-${RANDOM} kube-toolbox"
```

Now you can run `kbox`, and you will enter the BASH shell within the
kube-toolbox container. The home directory inside the container (`/root`) is
mounted to a persistent volume also called `kbox` (see it with `podman volume
ls`). You can save any files under `/root` and they will be persisted to the
volume, which includes Kubernetes API tokens, SSH keys, and any other config
files. A host directory (`${HOME}/git`) is mapped into the container to share
git repositories with the container, and to allow you to use a native file
editor on the host. `${HOME}/.gitconfig` is mounted as well, so that you do not
need to reconfigure git inside the container.

You should not be concerned about running as `root` inside this container, it is
intentional and safe. When running podman as a user, it is run *rootless*, which
means that it will map `root` inside the container to the same UID on the host
that ran podman (your regular workstation user ID, *not* the real root user.)
This means that when you create files in the container, as root, in `/root/git`,
they will show up in the host directory `${HOME}/git` owned by your regular
workstation user ID.

Enter the interactive sub-shell:

```bash
kbox
```

You will see the toolbox BASH prompt (`kube-toolbox`), indicating you are now inside the container:
```
[root@kube-toolbox ~]$
```

Create a new ssh key :

```bash
ssh-keygen
```

Also note, that the lifetime of the container is the lifetime of the shell
process, so as soon as you quit the shell, the container is removed (`podman run
--rm`). So if you install programs (alpine Linux `apk add`) or create files
(outside of `/root` or `/root/git`) they will be **gone** the next time you run
`kbox`. In order to permanently add additional programs, you should modify the
Dockerfile, and rebuild the image, as shown above.

## Setup podman-remote in toolbox container (optional)

The toolbox container cannot run other containers inside of itself. This means
that normally, you can only run `podman` or `docker` on the *host* workstation.
However, the toolbox container has installed `podman`, which is actually
`podman-remote` (just renamed to `podman`) which is a stripped version of podman
that is only used for connecting to a *remote* system and running podman on the
remote machine (this version of podman cannot run containers by itself.)

You can setup your host workstation to run podman, and configure the remote
access for the `kbox` container to use it, so that the container itself can run
normal podman (remote) commands, and have them run on the host podman. See the
upstream [podman-remote
instructions](https://github.com/containers/podman/blob/master/docs/tutorials/remote_client.md)
for setup, here is the gist:

 * You must enable ssh on the host workstation. 
 * You must copy the container root user ssh key (`/root/.ssh/id_rsa.pub`) into
   your host workstation user's authorized_keys file
   (`${HOME}/.ssh/authorized_keys`)
 * You must test that ssh works from within `kbox`, to the host workstation IP
   address: `ssh USER@X.X.X.X`
 * You must enable the podman systemd socket activation on the host workstation:
   `systemctl --user enable --now podman.socket`
   
Once ssh is tested to work, from `kbox` to your host workstation, you can add
the connection to podman. 

Run this inside `kbox`:

```env
HOST_WORKSTATION=workstation-host
HOST_USER=ryan
HOST_IP_ADDRESS=X.X.X.X
```

Setup the connection persistence on bash startup (run in `kbox`):

```bash
cat <<EOF >> ${HOME}/.bashrc
## Setup podman remote to host workstation:
podman system connection add \
  ${HOST_WORKSTATION} ssh://${HOST_USER}@${HOST_IP_ADDRESS} \
  --identity ~/.ssh/id_rsa
EOF
```

Now exit and restart `kbox` (press `Ctrl-D` or type `exit` and then retstart
`kbox`)

Inside the new `kbox` shell, list the podman connections: 

```bash
podman system connection list
```

You should see the workstation connection name listed, ending with an asterisk
(`*`) to indicate it is the default connection to use.

Test that you can list containers:

```bash
podman ps
```

You should see a list of all of the containers that are running on your host
workstation user account (which at least includes the running kbox container.)

Test that you can run the standard `hello-world` container:

```bash
podman run --rm -it hello-world
```
