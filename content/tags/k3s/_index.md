---
title: k3s
---
These are a series of blog posts about creating a single node [k3s](https://k3s.io/) (kubernetes) cluster, for the creation of a self-hosted devops environment, including:

 * Traefik reverse proxy
 * Gitea git hosting service
 * Container registry
 * Drone Continuous Integration

See technical notes and the full source code in the git repository
[README](https://github.com/EnigmaCurry/blog.rymcg.tech/tree/master/src/k3s#k3s-yaml-templates).

This series of posts contains detailed commands in blockquotes. Generally
speaking, all commands are intended to be reproducible on any modern Linux
environment, without modification, simply by copying and pasting these commands.

Here is an example of this style used throughout the blog:

This command is just setting an environment variable, giving you an opportunity
to modify it.

```bash
UPSTREAM=${HOME}/git/vendor/enigmacurry/blog.rymcg.tech
```

This command references the prior defined variable, letting you copy the commands without needing to modify it:
```bash
git clone https://github.com/EnigmaCurry/blog.rymcg.tech.git ${UPSTREAM}
cd ${UPSTREAM}/src/k3s
```

Each post builds upon the next, so you should start with part 1.
