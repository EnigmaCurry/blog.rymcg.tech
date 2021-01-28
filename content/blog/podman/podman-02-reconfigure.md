---
title: "Podman part 02: Reconfiguring"
date: 2021-01-18T00:01:00-06:00
tags: ['podman']
draft: true
---

After you have [deployed podman and some containers via
cloud-init](/blog/podman/podman-01-cloud-init/), you may wish to reconfigure the
system, add containers, or change existing ones. cloud-init is only designed to
run on first boot, so how do you reconfigure the deployments later on?

Fortunately, the `podman_trafik` script created a copy of itself at
`/usr/local/sbin/podman_traefik.sh`. This file looks a bit different than the
initial script we used. It has transformed! The installed script contains *both*
the original podman_traefik functions *and* your own configuration in *one* new
file.

You can edit `/usr/local/sbin/podman_traefik.sh`, change the configuration, and
re-reun it. Your services will be reconfigured and restarted.

The new installed `podman_traefik` script looks like this:

```
ALL_TEMPLATES=(....)
default_config() { ... }
config() { ... }
create_service_container () { ... }
create_service_proxy () { ... }
traefik_service () { ... }
whoami_service () { ... }
install_packages() { ... }
```

