# k3s YAML templates

These are the kubernetes resources from [EnigmaCurry's blog posts about
k3s](https://blog.rymcg.tech/tags/k3s/)

## Features

 * Single node deployment - Easy! No concern for high-availability. (but you
   could still do that, if you build this up.)
 * Simple [bash script](render.sh) runs
   [envsubst](https://linux.die.net/man/1/envsubst) rather than helm charts.
   Simple environment variable substituion rather than a full templating
   language.
 * All configuration done through shell variables, sourced from environment
   files. For any missing information, it is queried and interactively input
   during render.
 * [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) to
   cryptographically store secrets (passwords, tokens, keys etc.), directly in
   git source control. Decrypted secrets are only accessible to authorized
   cluster resources.
 * Just use `kubectl` directly to install YAML. Also check out the bash
   functions `kube_apply` and `kube_delete` in [util.sh](util.sh) which is
   useful for working with globs of files (eg. `drone.*.yaml`)
 * Custom (non k3s-default) [Traefik
   v2](https://github.com/traefik/traefik#overview) Ingress controller. Traefik
   supports HTTP, HTTP(s) (with automatic ACME / Let's Encrypt certificate
   generation) and TCP. Along with traditional HTTP based Ingress, you can run
   TCP services like SSH, inside a container, and route it through Traefik!
   
Start by reading the [first post on the
blog](https://blog.rymcg.tech/blog/k3s/), in order to install k3s, traefik and
learn about `render.sh`, the environment files, and templates.
