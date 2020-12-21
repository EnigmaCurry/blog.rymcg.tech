---
title: k3s
---

# Self-Hosted Literate K3s Cluster

This series of blog posts is a Literate Programming notebook for the BASH shell,
for the bootstrapping of a self-hosted [K3s](https://www.k3s.io) kubernetes
cluster using GitOps (Git+DevOps) principles. [Flux (v2)](https://fluxcd.io/) is
a controller that runs on top of kubernetes, that will synchronize your git
repositories containing all of your kubernetes manifests (YAML), and
automatically apply changes to your cluster. With Flux, you can administer all
of your kubernetes infrastructure via pull request!

Self-hosted means running full-stack, open-source software, on top of commodity
computer hardware or virtual machines, with as little reliance on external
services as feasable. It doesn't mean you *have* to run on bare-metal hardware
that you built from transistors and Verilog, and host in your basement, but it
*does* mean that you should be able to do that if you want to! (The example
cluster will keep it simple and use a single DigitalOcean droplet instead. 😉)
Kubernetes is an abstraction that makes the host platform irrelevant, giving you
this freedom back. You can run the same workloads in K3s as you can in any other
enterprise kubernetes host. K3s is easy to install, and runs just about
anywhere, on bare-metal, on virtual machines (droplets), in docker, as well as
several different CPU architectures. However, this blog will only focus on using
the `amd64` architecture. **Sorry, Raspberry Pis are NOT tested to work** with
these instructions. 

In this series, you will learn, and more:
 * How to setup your workstation for all development tools.
 * How to create a k3s cluster.
 * How to host [Traefik](https://traefik.io/) (v2) to proxy HTTP and TCP traffic
   (Ingress) to your applications, giving you free TLS (https) certificates from
   [Let's Encrypt](https://letsencrypt.org/) (best option for public websites)
   or from your private Certificate Authority via
   [Step-CA](https://smallstep.com/docs/step-ca) (for private APIs and Mutual
   TLS) (Only Step CLI with an offline CA described thus far [most secure
   option], but you could run your own online ACME CA if you want to [but harder
   to secure].)
 * How to host your own public and private git repositories in
[Gitea](https://gitea.io/) (and how to mirror them to GitHub for backup.)
 * How to host [Flux (v2)](https://fluxcd.io/), such that your cluster state is
   driven by your git repository state. (use `git push`, not `kubectl apply`)
 * How to host a private container registry for hosting your own container
   images.
 * How to host simple applications like Wordpress, and the MySQL database.

Literate means to use [Literate
Programming](https://en.wikipedia.org/wiki/Literate_programming) concepts. You
just need a web-browser and a terminal. There are literal code blocks for you to
copy and paste into your BASH terminal to reproduce all of the files and
commands necessary for this setup. There is *no* additional git repository you
need to clone or fork. The commands you see on this blog are all you need, in
order to create your own self-hosted git repository, from scratch. This will all
be explained in detail in [Part 1](/blog/k3s/k3s-01-setup/).

{{< about_footer >}}
