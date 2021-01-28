---
title: "K3s part 13: Building containers (images) with Drone"
date: "2020-12-28T00:13:00-06:00"
tags: ['k3s']
draft: true
---

With the use of the development Drone runner you created in [part
12](/blog/k3s/k3s-12-drone-development/), you can now build container images as
part of a Drone pipeline.

## Container to build containers

Let's build a container that can build other containers, using docker. Create a
new git repository for container image Dockerfiles.

```env
CLUSTER=k3s.example.com
REGISTRY=registry.${CLUSTER}
CONTAINER_GIT_SRC=${HOME}/git/containers
```

```bash
mkdir -p ${CONTAINER_GIT_SRC}/build/docker
git -C ${CONTAINER_GIT_SRC} init
cat <<EOF > ${CONTAINER_GIT_SRC}/build/docker/Dockerfile
FROM alpine:latest
RUN apk --no-cache add docker-cli
EOF
```

Build the image:

```bash
docker build -t ${REGISTRY}/build/docker ${CONTAINER_GIT_SRC}/build/docker
```

Retrieve registry credentials, and login to the registry:

```bash
get_secret() { kubectl -n registry get secret registry -o json | \
    jq -r .data.$1 | base64 -d ;}
docker login ${REGISTRY} -u $(get_secret REGISTRY_ADMIN) \
   -p $(get_secret REGISTRY_PASSWORD)
``` 

Push the image:

```bash
docker push ${REGISTRY}/build/docker
```


