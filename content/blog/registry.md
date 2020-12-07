---
title: "k3s part 3: Container Registry"
url: "blog/registry"
date: 2020-12-01T13:32:03-07:00
tags: ['k3s', 'kubernetes']
draft: false
---

## Abstract

 * This is part 3 of the [k3s](/tags/k3s/) series. 
 * You will create and host a private, password protected, container registry for
   storing and distributing your OCI (docker) container images.
 * You will configure your k3s cluster to pull images from your private
   registry.
 * You will store images in an external durable S3 service (DigitalOcean Spaces).

## Edit Template Variables

Make sure you have followed [part 1](/blog/k3s) and have your terminal open to
the configuration directory we previously created (and already contains
`render.sh`).

```bash
# The directory we used in part 1:
cd ${HOME}/git/vendor/enigmacurry/blog.rymcg.tech/src/k3s
# pull the latest changes:
git pull
```

Edit the environment file for the registry, contained in `registry/env.sh`.

Review and make changes to the following variables:

 * `ADMIN_USER` the name of the registry user to login as (default: `admin`)
 * `DOMAIN` the domain name for the registry (You'll see that it's commented
   out, which will force render.sh to ask you to input it each time you render.
   You may uncomment `DOMAIN` in order to hard-code the value and have it not
   ask.)

## Prepare an S3 bucket

You may use any S3 compatible storage bucket (DigitalOcean Spaces, AWS S3,
minio, etc.) This will describe how to use DigitalOcean Spaces.

 * From the DigitalOcean console [create a new Space (S3
   bucket)](https://cloud.digitalocean.com/spaces/new)
 * Choose a datacenter region.
 * Do not enable CDN.
 * Choose `Restrict File Listing` (default)
 * Choose a unique name for the Space
 * Finalize and Create the Space
 * Go the settings for the new Space and find the `Endpoint` domain name and
   make a note of it for the next steps. The name before the first `.` is the
   region name, for example if the endpoint is `sfo2.digitaloceanspaces.com` the
   region is just `sfo2`.
 * Create a new [Spaces Access
   Key](https://cloud.digitalocean.com/account/api/tokens), the recommended name
   for the key is the full domain name of the registry. It will generate two
   strings: the access key and the secret key. You will need to save these for
   the next step.
   
## Render the templates

After the environment has been configured, render the templates:

```bash
./render.sh registry/env.sh
```

Passwords and keys will be randomly generated and stored in the sealed secret
(Sealed Secrets were first discussed in [part 2](/blog/gitea#sealed-secrets).

The render script will ask you a series of questions about other variables that
you have not yet specified in the environment (listed as `ALL_VARS` and
`ALL_SECRETS`). Enter the appropriate values when it prompts you.

 * `S3_ACCESS_KEY` - the access key from `Spaces Access Key` value generated in
   the last step.
 * `S3_SECRET_KEY` - the secret key from the `Spaces Access Key` value generated
   in the last step.
 * `S3_REGION` - the region name (ie `sfo2`)
 * `S3_ENDPOINT` - the S3 endpoint domain (ie `sfo2.digitaloceanspaces.com`) 
 * `S3_BUCKET` - the unique Spaces name (S3 bucket name).

The randomly generated admin password is printed in the output. Copy this
password for use in the next steps.

## Apply the YAML

Once the templates have been rendered, apply them to your cluster:

```bash
kubectl apply -f registry.configmap.yaml \
              -f registry.ingress.yaml \
              -f registry.sealed_secret.yaml \
              -f registry.yaml 
```

## Check it works

From your workstation, you can interact with the registry using
[podman](https://podman.io/getting-started/installation) or
[docker](https://docs.docker.com/engine/install/). These instructions assume
podman, but the interface is identical, so if you are using docker, just replace
`podman` with `docker`.

Pull any example test image from the global docker hub registry. This will make
the image available locally on your workstation:

```bash
podman pull functions/figlet:latest
```

Set a variable for your own registry domain name:

```bash
DOMAIN=registry.k3s.example.com
```

Tag the image for your registry:

```bash
podman tag functions/figlet:latest ${DOMAIN}/functions/figlet:latest
```

Now we want to test that no one can access the registry unless they are logged
in. Attempt to push the image to the registry. It should fail with an error
because you have not logged in yet:

```bash
podman push ${DOMAIN}/functions/figlet:latest
```

You should see an error message that, in part, says `unauthorized:
authentication required`

Now try logging in:

```bash
podman login ${DOMAIN}
```

Enter the username (admin) and the generated password from the prior step. If
successful, it should print `Login Succeeded!`

Now retry pushing the image to your registry:

```bash
podman push ${DOMAIN}/functions/figlet:latest
```

This time it should successfully copy the image to the registry.

You can also verify that the S3 storage is working correctly by observing the
new files created. Use the DigitalOcean console to view the Space and see the
new `docker` directory created and sub-directories that contain the uploaded
image layers.

## Configure k3s to utilize your private registry

By default, k3s is setup to use only the global docker.io registry (Docker Hub).
A better, more secure option, is to override the global registry (`docker.io`)
with your own private registry. This means that your cluster will only be able
to run images that are contained in your private registry. Any public images
that you need must be manually pulled from the global registry and pushed to
your private registry (`podman push`).

See the [k3s
docs](https://rancher.com/docs/k3s/latest/en/installation/private-registry/) for
full details on how to do this.

This is inconvenient when you want to run images that are not contained in your
private registry. So Instead of doing that, we will add our own private registry
**in addition to** the global registry. This will allow us to pull images that
are public or private depending on the image prefix specified. Images with no
registry prefix will be pulled from `docker.io` and images prefixed with our
registry name will be pulled from our registry.

You will create a new file on the host k3s server called
`/etc/rancher/k3s/registries.yaml`:

```
mirrors:
  example.com:
    endpoint:
      - "https://registry.k3s.example.com"
configs:
  "registry.k3s.example.com":
    auth:
      username: admin
      password: xxxxx
```

You will need to replace the example domain names with your own (three places).
Enter the admin password you generated above.

Set appropriate permissions for this file:

```bash
chmod 0600 /etc/rancher/k3s/registries.yaml
```

In order for this change to take effect, you must restart all of the nodes
of your cluster. Run this on each node:

```bash
systemctl restart k3s
```

Now when you specify an image like `containous/whoami` it will pull from the
regular docker hub. Likewise, if you specify and image like
`docker.io/containous/whoami` it will pull from the regular docker hub. If you
put your own domain name as the prefix, like `example.com/containous/whoami` it
will attempt to pull the image from your private registry, and if you have not
previously pushed that image, it will fail to pull it.

Try running an image that is not contained in your registry:

```bash
kubectl run --image=example.com/containous/whoami test-whoami
```

Use `kubectl describe` to show the expected error message:

```bash
kubectl describe pod test-whoami
```

You should see an error `Error: ErrImagePull`. This is the expected error when
the image does not exist.

Delete the `test-whoami` pod:
```bash
kubectl delete pod test-whoami
```

Now try running the same image, but directly from docker.io (default with no
`docker.io` prefix required)

```bash
kubectl run --image=containous/whoami test-whoami
```

See that it pulled the image and started correctly:

```bash
kubectl describe pod test-figlet
```

You should see messages like `Successfully pulled image "containous/whoami"` and
`Started container test-whoami`.

Delete the `test-whoami` pod:
```bash
kubectl delete pod test-whoami
```


## Links

https://github.com/alexellis/k8s-tls-registry
https://rancher.com/docs/k3s/latest/en/installation/private-registry/
https://doc.traefik.io/traefik/https/tls/#client-authentication-mtls

