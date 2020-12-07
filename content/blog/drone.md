---
title: "k3s part 4: Drone - Continuous Integration (CI)"
url: "blog/drone"
date: 2020-12-04T13:32:03-07:00
tags: ['k3s', 'kubernetes']
draft: true
---

## Abstract

 * This is part 4 of the [k3s](/tags/k3s/) series. 
 * You will install [drone](https://www.drone.io/), a self-hosted Continuous
   Integration platform.
 * Drone will connect to gitea to run jobs in response to changes made to git
   repositories.
 * You will setup a job runner in order to build a container image, from a
   Dockerfile, whenever the file changes in git, and push the image to your
   container registry.

## Prerequisites

Make sure you have followed [part 1](/blog/k3s) and have your terminal open to
the configuration directory we previously created (and already contains
`render.sh`).

```bash
# The directory we used in part 1:
cd ${HOME}/git/vendor/enigmacurry/blog.rymcg.tech/src/k3s
# pull the latest changes:
git pull
```

Make sure you have followed [part2](/blog/gitea) and created the gitea service.

Make sure you have followed [part3](/blog/registory) and created the registry
service.

## Building container images with Drone

Building container images with docker, or even podman, requires some special
privileges that are not normally given to regular containers. Building
containers *inside* containers, without the security risks of running privileged
containers, is not a trivial task. I've found two ways to do it though, one with
[buildah](https://flavio.castelli.me/2020/09/16/build-multi-architecture-container-images-using-kubernetes/)
and one with
[GoogleContainerTools/kaniko](https://github.com/GoogleContainerTools/kaniko),
however, both of these solutions are quite fragile and have several caveats. At
least for the time being, it seems that building container images is a task best
suited for Virtual Machines, and not containers.

Luckily, Drone runners will run lots of different places, and not just in
containers.

Today we'll be looking at the [DigitalOcean Drone
runner](https://docs.drone.io/runner/digitalocean/overview/), which will run
Drone pipelines on a droplet. This will work nicely for building our container
images, as droplets are KVM (kernel virtual machines, not containers). We can
run podman or docker directly on a droplet, in order to build our container
images. Droplets will be created on the fly, build the image, upload the image
to the registry, and then the droplet gets destroyed. DigitalOcean droplets are
billed hourly, and one droplet is created for each (configured) pipeline and
then destroyed, so this is a bit of a waste if the pipeline only takes 5
minutes. A $5 droplet, billed hourly, is $5/(30 days * 24 hours) = $0.007/hour.
So that's half a cent for every job, under an hour, that you send to
DigitalOcean. You do the math to see if it makes sense. Assuming your images
only get built rarely, it still seems like a great deal.

Your Drone instance will need to hold your DigitalOcean API token as a secret
(stored as a k8s sealed secret). For security reasons, you should create a brand
new separate DigitalOcean team account to dedicate to drone usage. You can do
this from an existing DigitalOcean billing account. In the top right of the
DigitalOcean console, select [Create a
team](https://cloud.digitalocean.com/account/team/new).

From the newly created team account, go to
[API](https://cloud.digitalocean.com/account/api/tokens) and click `Generate New
Token`. Give the name as the fully qualified domain name of your drone instance
(`drone.k3s.example.com`). Keep this page open for easy copying of the generated
key, once you close this page you won't be able to see it again, and you'll have
to regenerate it.

## Create Gitea OAuth2 app

 * Go to your personal settings page in gitea.
 * Click `Applications`
 * Find `Create a new OAuth2 Application`
 * Enter the `Application Name` (`drone`)
 * Enter the `Redirect URI` (`https://drone.k3s.example.com/login`)
 * Click `Create Application`
 * Find the generated `Client ID` and `Client Secret`, you will need to enter
   these when you render the templates in the next step.
   
## Edit Template Variables

Edit the environment file for drone, contained in `drone/env.sh`.

Here is a list of the variables that you may configure. Any variables that you
do not specify in the env.sh file are asked for interactively at render time. So
you don't need to edit anything if you just want to be asked by render.sh.

 * `DOMAIN` - the domain name for drone (eg. `drone.k3s.example.com`)
 * `PVC_SIZE` - the size of the data volume for drone. I don't really know what
   the appropriate size is for this yet, I have defaulted it to `10Gi`.
 * `DRONE_GITEA_SERVER` - this should be the full gitea service URL (starting
   with `https://`) (eg. `https://gitea.k3s.example.com`)
 * `DRONE_SERVER_HOST` - the domain name of the drone service (eg
   `drone.k3s.example.com`)
 * `REGISTRY_DOMAIN` the domain name of the registry (eg `registry.k8s.example.com`)
 * `REGISTRY_USER` the username to authenicate with the registry.
 * `REGISTRY_PASSWORD` the password to authenticate with the registry.
 * `DRONE_GITEA_CLIENT_ID` - the OAuth2 client ID generated in the last step.
 * `DRONE_GITEA_CLIENT_SECRET` - the OAuth2 client ID generated in the last step.
 
## Render templates

Render the templates:

```bash
./render.sh drone/env.sh
```

Enter all the requested information, including the Client ID and Client Secret
from the OAuth2 app inside gitea.

This creates new yaml and the sealed_secret.

## Apply the YAML

Apply the yaml to your cluster. There is a small bash function defined in
[util.sh](https://github.com/EnigmaCurry/blog.rymcg.tech/blob/master/src/k3s/util.sh)
called `kube_apply`. It lets you run `kubectl apply` with a glob of files like
`drone.*.yaml`.

```bash
source util.sh
```

```bash
kube_apply drone.*.yaml
```

You may need to run it twice, depending on if you get a dependency error, the
second time it should resolve any.

You can also use `kube_delete` the same way, just be careful to not include the
namespace or pvc files if you want to keep those data volumes!

Remember to commit and push your new/modified yaml to your git repository.

## Check it works

List all of the pods, and check they have started

```bash
kubectl -n drone get pods
```

If there are any not starting describe them to see the error message:

```bash
kubectl -n drone describe pod NAME
```

If everything started, go to the URL for drone, `https://drone.k3s.example.com`
it should redirect back to your gitea instance with an authorization message to
allow drone to connect to gitea. Confirm the authorization, and you will be
redirected back to drone and you are now logged in as your gitea user.

## Create a simple Job Pipeline

Create a new repository
 
 * Go to your gitea instance, and click the `+` icon, and `New Repository`, type
   a name `test-drone` and click `Create Repository`. Make a note of the SSH
   clone URL.
 * Go to your drone instance, and click `Sync` to refresh the list of
   repositories. Find the new repository called `test-drone` and click
   `Activate`, then `Activate Repository`.
 * Clone the repo to your workstation, via SSH:
 
```bash
DIR=${HOME}/git/test-drone
git clone ssh://git@git.k3s.example.com:2222/user/test-drone.git ${DIR}
cd ${DIR}
```

Create new file `.drone.yml`, put this yaml inside:

```yaml
kind: pipeline
type: kubernetes
name: default

steps:
- name: hello-world
  image: alpine:3
  commands:
  - echo hello world
  - echo bye
```

Add, Commit, and Push the change to the gitea repository:

```bash
git add .drone.yml
git commit -m "hello-world"
git push
```

Go to your drone instance, and find the `test-drone` repository again. You
should see a new job in the Activity Feed called `hello-world` (Or whatever your
git commit message was.) At the bottom you should see the step called
`hello-world` and in the output you should see the message `hello world` and
`bye`. The job is working!

You can find more complex job pipeline examples in the [drone
docs](https://docs.drone.io/pipeline/kubernetes/examples/)

## Create a DigitalOcean pipeline to build a container image

For jobs that can't (easily) run in k8s containers, we can send them to
DigitalOcean instead.

In your `test-drone` repository, create a file called `Dockerfile`:

```
FROM alpine:3
CMD ["/bin/sh", "-c", "echo helllo wooorld"]
```

Edit the `.drone.yml` and add the following to the end:

```yaml
---
kind: secret
name: digitalocean_api_key
get:
  path: drone
  name: DIGITALOCEAN_API_TOKEN
---
kind: pipeline
type: digitalocean
name: digitalocean-docker-builder

token:
  from_secret: digitalocean_api_key

server:
  image: docker-18-04
  size: s-1vcpu-1gb
  region: nyc1

steps:
- name: build
  commands:
  - docker build -t ${REGISTRY_DOMAIN}/enigmacurry/hello-world .
  - docker run ${REGISTRY_DOMAIN}/enigmacurry/hello-world
```

Commit both files to git and push the changes to the gitea remote.
