---
title: "K3s part 12: Drone development"
date: "2020-12-28T00:12:00-06:00"
tags: ['k3s']
---

This post directly follows the work done in [Part 11](/blog/k3s/k3s-11-drone),
where Drone was setup, and test jobs were made to run on the cluster. Still,
some workloads are not well suited to running inside of Kubernetes. Ironically,
one of these unsuitable workloads is building container images. Generally
speaking, container images are built with `docker` or `podman`, or some other
container builder tool, but these tools need to run on the host system, or
require special privileges assigned to the container that they are run in. Its
not impossible to secure container builds, and there are notable methods to do
so, but they come with caveats:

 * [buildah](https://developers.redhat.com/blog/2019/08/14/best-practices-for-running-buildah-in-a-container/)
   can be made to run in a "normal root container", but still requires to mount
   the `/dev/fuse` device. In theory this should be possible on kubernetes (but
   not on rootless podman?)
 * [kaniko](https://github.com/GoogleContainerTools/kaniko) can build containers
   without any privileges, but its pretty experimental, and only works for
   amd64.
   
Due to these complexities, building container images inside the cluster, is a
goal that will be deferred for now. Luckily, Drone offers to run workloads in
lots of places, *outside* of the cluster.

For development purposes, this post will describe how to create a VM on your
workstation, install Docker inside that VM, and then install the [Drone Docker
runner](https://docs.drone.io/runner/docker/overview/). Jobs to build container
images, will live inside of privileged docker containers, running inside of the
VM, and run `docker build` using docker-in-docker. This method is insecure by
default, but is more acceptable to do inside the VM. (which can be easily wiped)

NOTE: Vagrant is **not installed** in the `kbox` utility container (which you
might have created if you followed [part
1](/blog/k3s/k3s-01-setup/#create-toolbox-container-optional)). **You must run
all of these commands on your host workstation.**

## Create Vagrant KVM instance

```env
## Vagrant will read this var and put Vagrantfile in this directory:
export VAGRANT_CWD=${HOME}/git/vagrant/drone-docker
```

```bash
mkdir -p ${VAGRANT_CWD}
vagrant init generic/debian10 && vagrant up
```

## Install Docker on the VM

Install docker through `vagrant ssh`, run this on your host workstation:

```bash
cat <<'EOF' | vagrant ssh
sudo apt update && \
sudo apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common && \
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add - && \
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable" && \
sudo apt-get update && \
sudo apt-get -y install docker-ce docker-ce-cli containerd.io
EOF
```

You can check that the docker service started:

```bash
vagrant ssh -- systemctl status docker
```

## Install Drone Docker Runner

You will need to provide the drone runner with the same `RPC_SECRET` and
`KUBERENETES_SECRET_KEY` used when installing Drone. You can find this
information by pulling it from the Secret, via kubectl.

```env
NAMESPACE=drone
RUNNER=vagrant-development
## runner labels to route jobs to this runner:
RUNNER_LABELS=docker-development:true
```

```bash
## Retrieve your secrets and store as variables:
get_secret() { kubectl -n ${NAMESPACE} get secret drone -o json | \
    jq -r .data.$1 | base64 -d ;}
RPC_SECRET=$(get_secret RPC_SECRET)
KUBERNETES_SECRET_KEY=$(get_secret KUBERNETES_SECRET_KEY)
SERVER_HOST=$(get_secret SERVER_HOST)
```

Now install the drone runner:

```bash
cat <<EOF | vagrant ssh
sudo docker run -d \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DRONE_RPC_PROTO=https \
  -e DRONE_RPC_HOST=${SERVER_HOST} \
  -e DRONE_RPC_SECRET=${RPC_SECRET} \
  -e DRONE_RUNNER_CAPACITY=2 \
  -e DRONE_RUNNER_NAME=${RUNNER} \
  -e DRONE_RUNNER_LABELS=${RUNNER_LABELS} \
  -p 3000:3000 \
  --restart always \
  --name drone-runner \
  drone/drone-runner-docker:1
EOF
```

Destroy the evidence:

```bash
unset RPC_SECRET KUBERNETES_SECRET_KEY SERVER_HOST
```

Check the drone runner started:

```bash
vagrant ssh -- sudo docker logs drone-runner
```
