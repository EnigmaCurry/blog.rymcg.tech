---
title: k3s
---

# K3s

These posts are about building a self-hosted [K3s](https://www.k3s.io)
kubernetes cluster using DevOps (GitOps) principles. [Flux
(v2)](https://fluxcd.io/) is a controller that runs on top of kubernetes, and
will synchronize your git repository containing all of the kubernetes manifests
(YAML), and automatically apply them to your cluster. With Flux, you can manage
all of your infrastructure via pull request!

Self-hosted means running full-stack open-source software on top of commodity
hardware or virtual machines. It doesn't mean you have to run on bare-metal
hardware that you personally own or host, but it *does* mean that you should be
able to do that! Kubernetes is an abstraction that makes the host platform irrelevant,
giving you this freedom back. You can run the same workloads in K3s as you can
in any other enterprise kubernetes host. K3s is easy to install, and runs just
about anywhere, on bare-metal, on virtual machines, in docker, as well as
several different CPU architectures. However, this blog will only focus on using
the `amd64` architecture. **Raspberry Pis are NOT tested to work** with these
instructions.

Start with [Part 1](/blog/k3s/k3s-01-setup/)

{{< matrix_room >}}
