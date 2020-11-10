---
title: "k3s part 2 : Gitea"
date: 2020-11-02T15:23:30-08:00
draft: true
---

# Abstract
 
 * This is part 2 of the [k3s](/tags/k3s/) series. 
 * You will install [gitea](https://gitea.io/) on your cluster, in order to host
   private git repositories.

Self-hosting our own git repositories will serve as the backbone of later
development and deployment projects, so its one of the first things we want to
install on our cluster. Gitea is an open-source lightweight github-like
experience without external service dependencies, allowing us to create and
publish private and/or public git repositories.

# Prepartion

Make sure you have followed [part 1](/blog/k3s) and have your terminal open to
the configuration directory we previously created.

```bash
cd $HOME/git/k3s
```


blah blah blah, once you have the templates rendered apply them to the cluster:

```
kubectl apply -f gitea.postgres.pvc.yaml \
              -f gitea.postgres.yaml \
              -f gitea.pvc.yaml \
              -f gitea.sealed_secret.yaml \
              -f gitea.yaml \
              -f gitea.ingress.yaml
```

Once it starts, create the initial admin user (Note that you *cannot* use the
username `admin`, which is reserved):

```
USERNAME=root
EMAIL=root@example.com
kubectl exec deploy/gitea -it -- gitea admin user create --username $USERNAME --random-password --admin --email ${EMAIL}
```

The password is randomly generated and printed, but its at the top of the
output, so you may need to scroll up to see it.
