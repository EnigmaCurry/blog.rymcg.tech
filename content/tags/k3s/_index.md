---
title: k3s
---
These are a series of blog posts about creating a single node [k3s](https://k3s.io/) (kubernetes) cluster, for the creation of a self-hosted devops environment, including:

 * Traefik reverse proxy
 * Gitea git hosting service
 * Container registry
 * Drone Continuous Integration

This blog will focus on the kubernetes YAML abstraction, not on further
abstractions, like helm. This blog uses a simple bash script to create YAML
files from templates, using regular shell environment variables. See the
technical notes and the full source code in the git repository
[README](https://github.com/EnigmaCurry/blog.rymcg.tech/tree/master/src/k3s#k3s-yaml-templates).
(Please note that this is in a subdirectory called `src/k3s` of a larger
mono-repository, [containing this entire
blog.](https://github.com/EnigmaCurry/blog.rymcg.tech))

These blog posts contain detailed commands, in block-quotes. Generally speaking,
all of these commands are intended to be reproducible on any modern Linux
workstation running the BASH shell, without modification, simply by copying and
pasting these commands. When a command does need to be customized, you will set
an environment variable for convenience of customizing the follow up commands,
which reference the temporary variable.

```bash
SOME_DIRECTORY=${HOME}/git/vendor/enigmacurry/blog.rymcg.tech
```
```bash
echo some command that references ${SOME_DIRECTORY} so you can just copy and run
```

Each post builds upon the next, so you should start with [part 1](/blog/k3s/).

You can discuss this blog on Matrix:
[#blog-rymcg-tech:enigmacurry.com](https://matrix.to/#/%23blog-rymcg-tech%3aenigmacurry.com).
