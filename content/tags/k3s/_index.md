---
title: k3s
---
These are a series of blog posts about creating a single node [k3s](https://k3s.io/) (kubernetes) cluster, for the creation of a self-hosted devops environment, including:

 * Traefik reverse proxy
 * Gitea git hosting service
 * Container registry
 * Drone Continuous Integration

This blog will focus on kubernetes, not further abstractions, like helm. This
blog uses a simple bash script to create YAML files from templates using regular
shell environment variables. See technical notes and the full source code in the
git repository
[README](https://github.com/EnigmaCurry/blog.rymcg.tech/tree/master/src/k3s#k3s-yaml-templates).

These blog posts contains detailed commands in blockquotes. Generally speaking,
all commands are intended to be reproducible on any modern Linux environment,
without modification, simply by copying and pasting these commands. When a
command does needs to be customized, a command to define an environment variable
will precede it, allowing you to customize the variable before its used in the
following command(s).

Each post builds upon the next, so you should start with part 1.
