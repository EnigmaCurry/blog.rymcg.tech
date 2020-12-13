---
title: k3s
---

# Self-Hosted Literate K3s Cluster

These posts are about building a self-hosted [K3s](https://www.k3s.io)
kubernetes cluster using GitOps (Git+DevOps) principles. [Flux
(v2)](https://fluxcd.io/) is a controller that runs on top of kubernetes, that
will synchronize your git repositories containing all of your kubernetes
manifests (YAML), and automatically apply changes to your cluster. With Flux,
you can manage all of your infrastructure via pull request!

Self-hosted means running full-stack, open-source software, on top of commodity
hardware or virtual machines. It doesn't mean you have to run on bare-metal
hardware that you built from transistors and Verilog, connected to the dialup
modem in the your basement, but it *does* mean that you should be able to do
that if you want to! Kubernetes is an abstraction that makes the host platform
irrelevant, giving you this freedom back. You can run the same workloads in K3s
as you can in any other enterprise kubernetes host. K3s is easy to install, and
runs just about anywhere, on bare-metal, on virtual machines, in docker, as well
as several different CPU architectures. However, this blog will only focus on
using the `amd64` architecture. **Sorry, Raspberry Pis are NOT tested to work**
with these instructions.

Literate means to use [Literate
Programming](https://en.wikipedia.org/wiki/Literate_programming). There are
literal code blocks for you to copy and paste into your BASH terminal to
reproduce all of the files and commands necessary for this setup. There is *no*
additional git repository you need to clone or fork, what you see on this blog,
is all you need. ([You totally can clone this blog, if you want to
though.](https://github.com/EnigmaCurry/blog.rymcg.tech)) This will all be
explained in detail in [Part 1](/blog/k3s/k3s-01-setup/).

{{< matrix_room >}}
