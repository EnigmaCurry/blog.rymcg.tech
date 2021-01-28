---
title: "K3s part 14: Building functions with Drone"
date: "2020-12-28T00:14:00-06:00"
tags: ['k3s']
draft: true
---

Following [part 10](/blog/k3s/k3s-10-openfaas/), you have installed OpenFaaS,
and have tested a function from a manually built image. To automate this
procedure, you will use Drone to build container images for your functions,
directly from git source code.

You will use the development Drone runner you created in [part
12](/blog/k3s/k3s-12-drone-development/), which is now running inside a VM on
your workstation.

## Create repository

You previously created a repository to hold OpenFaaS functions in [part
10](/blog/k3s/k3s-10-openfaas/):

You need to create this same repository on Gitea.

 * Login to your Gitea account (https://git.k3s.example.com)
 * Create a new repository using the `+` icon in the upper right of the page.
 * Suggested repository name is `functions`. 
 * Find the SSH clone URL of the blank repository.

```env
CLUSTER=k3s.example.com
# Same repository used in part 10:
FUNCTIONS_ROOT=${HOME}/git/functions
# Enter the full git remote URL ssh://...
GIT_REMOTE=xxx
```

Add the gitea remote to the local repository:

```bash
git -C ${FUNCTIONS_ROOT} remote add origin ${GIT_REMOTE}
```

## Create drone pipeline

```bash
cat <<EOF > ${FUNCTIONS_ROOT}/.drone.yml
kind: pipeline
type: docker
name: default

steps:
- name: build
  image: openfaas/faas-cli
  commands:
  - echo hi there openfaas yeaa

node:
  docker-development: true
EOF
```

## Commit files

```bash
git -C ${FUNCTIONS_ROOT} add .
git -C ${FUNCTIONS_ROOT} commit -m "drone test"
```

```bash
git -C ${FUNCTIONS_ROOT} push -u origin master
```
