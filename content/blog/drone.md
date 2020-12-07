---
title: "k3s part 4: Drone - Continuous Integration (CI)"
url: "blog/drone"
date: 2020-12-04T13:32:03-07:00
tags: ['k3s', 'kubernetes']
---

## Abstract

 * This is part 4 of the [k3s](/tags/k3s/) series. 
 * You will install [Drone](https://www.drone.io/), a self-hosted Continuous
   Integration platform. Drone is the self-hosted equivalent of GitHub Actions,
   or Travis CI, or similar.
 * Drone will connect to gitea to run jobs in response to changes made to git
   repositories.
 * You will create a simple job runner that executes job pipelines directly
   inside k3s pods.
 * You will configure Drone to also create on-demand DigitalOcean droplets, in
   order to run build pipelines for things not compatible with containers (like
   making container images).
 * You will make a pipeline to build a container image, from a Dockerfile, on
   `git push`, and upload the image to your private container registry.

   
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

Examine the environment file for drone, contained in `drone/env.sh`. The env.sh
file is already setup with appropriate default values. The variables that are
commented out are designed to be asked for at render time. So you don't need to
enter any specific values into env.sh unless you wish to change the defaults!
render.sh asks for all of the variables listed in `ALL_VARS` and `ALL_SECRETS`.
Secret values are stored encrypted in a sealed secret.

Here is a description of the variables that you **may** configure in env.sh, or
you will be asked for interactively if you don't specify:

 * `DOMAIN` - the domain name for drone (eg. `drone.k3s.example.com`)
 * `PVC_SIZE` - the size of the data volume for drone. I don't really know what
   the appropriate size is for this yet, I have defaulted it to `10Gi`.
 * `DRONE_GITEA_SERVER` - this should be the full gitea service URL (starting
   with `https://`) (eg. `https://git.k3s.example.com`)
 * `DRONE_SERVER_HOST` - the domain name of the drone service (eg
   `drone.k3s.example.com`)
 * `REGISTRY_DOMAIN` the domain name of the registry (eg `registry.k8s.example.com`)
 * `REGISTRY_USER` the username to authenicate with the registry.
 * `REGISTRY_PASSWORD` the password to authenticate with the registry.
 * `DRONE_GITEA_CLIENT_ID` - the OAuth2 client ID generated in the last step.
 * `DRONE_GITEA_CLIENT_SECRET` - the OAuth2 client ID generated in the last step.
 * `DIGITALOCEAN_API_TOKEN` - your DigitalOcean API token
 
## Render templates

Render the templates:

```bash
./render.sh drone/env.sh
```

Enter all the requested information, including the Client ID and Client Secret
from the OAuth2 app inside gitea.

This creates new yaml and the sealed_secret. In the output copy the value for
`SSH_PUBLIC_KEY`. In the DigitalOcean console, go to
[Settings->Security](https://cloud.digitalocean.com/account/security) and click
`Add SSH Key`. Paste the value from the generated `SSH_PUBLIC_KEY` from the
render.sh output. Give the SSH key a name, ie. the full drone instance URL.

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

If there are any that are not starting, use `kubectl describe` to see the error
message:

```bash
kubectl -n drone describe pod POD_NAME
```

If everything started, go to the URL for drone, `https://drone.k3s.example.com`
it should redirect back to your gitea instance with an authorization message to
allow drone to connect to gitea. Confirm the authorization, and you will be
redirected back to drone and you are now logged in as your gitea user.

## Create a simple Job Pipeline

Create a new repository, using gitea.
 
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

Create a new file called `.drone.yml` (Note that the preceding `.` means it is a
hidden file, listable via `ls -la`.). Put this yaml inside:

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

Note the `type: kubernetes`, this means that the pipeline will run directly on
the cluster, as a pod.

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
kind: pipeline
type: digitalocean
name: digitalocean-docker-builder

token:
  from_secret: digitalocean_api_token

server:
  image: docker-18-04
  size: s-1vcpu-1gb
  region: nyc1

steps:
- name: build
  commands:
  - docker build -t $REGISTRY_DOMAIN/enigmacurry/hello-world .
  - docker run $REGISTRY_DOMAIN/enigmacurry/hello-world
  - docker login --username $REGISTRY_USER --password $REGISTRY_PASSWORD $REGISTRY_DOMAIN
  - docker push $REGISTRY_DOMAIN/enigmacurry/hello-world
  environment:
    REGISTRY_DOMAIN:
      from_secret: registry_domain
    REGISTRY_USER:
      from_secret: registry_user
    REGISTRY_PASSWORD:
      from_secret: registry_password
---
kind: secret
name: digitalocean_api_token
get:
  path: drone
  name: DIGITALOCEAN_API_TOKEN
---
kind: secret
name: registry_domain
get:
  path: drone
  name: REGISTRY_DOMAIN
---
kind: secret
name: registry_user
get:
  path: drone
  name: REGISTRY_USER
---
kind: secret
name: registry_password
get:
  path: drone
  name: REGISTRY_PASSWORD
```

Note the `type: digitalocean`, this pipeline will spawn a new DigitalOcean
droplet and run the entire pipeline on the droplet, and then destroy the
droplet.

Commit both files to git and push the changes to the gitea remote.

Check the output of the job for any errors. Your image should now be pushed to
the registry, test it by running:

```bash
podman run --rm -it registry.k3s.example.com/enigmacurry/hello-world
```

