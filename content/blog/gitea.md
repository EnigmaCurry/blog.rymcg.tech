---
title: "k3s part 2 : Gitea"
date: 2020-11-02T15:23:30-08:00
tags: ['k3s', 'kubernetes']
---

## Abstract
 
 * This is part 2 of the [k3s](/tags/k3s/) series. 
 * You will install [gitea](https://gitea.io/) on your cluster, in order to
   self-host git repositories, similar to github.
 * You will install postgresql in order to serve the database for gitea.
 * Ingress for HTTP and git+SSH will be provided by Traefik, building upon [the
   prior post](/blog/k3s/).

Self-hosting our own git repositories will serve as the backbone of later
development and deployment projects, so its one of the first things we want to
install on our cluster. Gitea is an open-source lightweight github-like
experience without external service dependencies, allowing us to create and
publish private and/or public git repositories.

## Prepartion

Make sure you have followed [part 1](/blog/k3s) and have your terminal open to
the configuration directory we previously created (and already contains
`render.sh`).

```bash
# The directory we used in part 1:
cd $HOME/git/k3s
```

## Sealed Secrets

This deployment will require us to store some secret information: the username
and password to the postgresql database, and some internal gitea keys. We will
use [bitnami/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) in
order to keep these values encrypted while at rest, and can only be decrytped by
our running cluster. This means that we can safely store our entire
configuration, including keys and passwords, in git, without exposing these
secrets.

Install the [latest release of
sealed-secrets](https://github.com/bitnami-labs/sealed-secrets/releases). You
will need to install the client side tool called `kubeseal`, and also apply the
cluster side SealedSecret CRD with `kubectl apply`.

Once installed, you should see the `sealed-secrets-controller` started and
ready:

```bash
kubectl -n kube-system get deployment -l name=sealed-secrets-controller
```

## Config

Edit the `gitea/env.sh` file, review and change the following environment variables:

 * `DOMAIN` - the subdomain to serve gitea
 * `APP_NAME` - the human friendly name of the gitea service
 * `DISABLE_REGISTRATION` - if set `true` accounts need to be created manually
   (see below.)
 * `REQUIRE_SIGNIN_VIEW` - if set `true` then no public access is allowed
   without signing in.
 * `PVC_SIZE` - the storage volume size for all of the git repositories.
 * `DISABLE_GIT_HOOKS` - If set `false`, any user with Admin or Git Hooks
   permission can create git hooks. Git hooks are able to modify the container
   with root permissions, so you must trust all users that you give this
   permission. Set to `true` to completetly disable git hooks.

The variables `POSTGRES_USER`, `POSTGRES_PASSWORD`, `INTERNAL_TOKEN`,
`JWT_SECRET`, and `SECRET_KEY` are all secret values and are *generated
automatically* at render time and put into a sealed secret. You don't need to
enter them, but their values will be printed in the render output so that you
can verify them.

Render the templates:

```bash
./render.sh gitea/env.sh
```

Wait a minute for the gitea tokens/keys to generate (behind the scenes, this
spawns a pod called `gitea-keygen-$RANDOM` and calls the `gitea generate secret`
command and sets the variables for you, and cleans up the pod.)

A bunch of `gitea.*.yaml` files are now generated, notably
`gitea.sealed_secret.yaml` contains all of the secrets, and the entire gitea
config file, encrypted into a Sealed Secret. Only your cluster can decrypt this
file, so it is safe to commit this file inside your git repository, along with
the rest of your configuration.

Once you have these templates rendered, you can apply them to the cluster.

## Creating gitea on the cluster

```bash
kubectl apply -f gitea.postgres.pvc.yaml \
              -f gitea.postgres.yaml \
              -f gitea.pvc.yaml \
              -f gitea.sealed_secret.yaml \
              -f gitea.yaml \
              -f gitea.ingress.yaml
```

## Deleting gitea from the cluster

If you need to delete these resources, you can re-run ths same kubectl command
but change `kubectl apply` to `kubectl delete` (using the same `-f` parameters).
*Note that if you delete from `gitea.pvc.yaml` or `gitea.postgres.pvc.yaml` you
will be deleting the Persistent Volume Claims, which will in turn delete the
entire data volumes and all of your hosted git repositories!* So you may want to
exclude those files from the `kubectl delete` command.

Example to delete gitea except the persistent volume claims (pvc):

```bash
# To DELETE gitea (but not the data):
kubectl delete -f gitea.postgres.yaml \
               -f gitea.sealed_secret.yaml \
               -f gitea.yaml \
               -f gitea.ingress.yaml
```

## Check it works

Once it starts, from your web browser, you should be able to access the URL
`DOMAIN` you set. If not, check the logs:

```bash
kubectl logs deploy/gitea
```

## Initial account creation

You need to manually create the initial admin user (Note that you *cannot* use
the username `admin`, which is reserved), this example uses the name `root` and
the email address `root@example.com`:

```bash
USERNAME=root
EMAIL=root@example.com
```
```bash
kubectl exec deploy/gitea -it -- gitea admin user create \
    --username ${USERNAME} --random-password --admin --email ${EMAIL}
```

The password is randomly generated and printed, but its at the top of the
output, so you may need to scroll up to see it. Once you sign in using this
account, you can create additional accounts through the web interface.

## SSH git access

Sign in to your gitea account and add your SSH pubkey to your user settings (the
contents of your own `~/.ssh/id_rsa.pub`.) Create a new repository, and clone it
using the URL it provides.

For example:

```bash
git clone ssh://git@git.k3s.example.com:2222/root/test1.git
```

SSH is forwarded through Traefik.
