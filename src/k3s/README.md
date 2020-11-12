# k3s blog

These are the kubernetes resources from [my blog posts about
k3s](https://blog.rymcg.tech/tags/k3s/)

## Features

 * Single node deployment - Easy! No concern for high-availability. (but you
   could still do that, if you build this up.)
 * Simple bash script runs `envsubst` rather than helm charts. Simple
   environment variable substituion rather than a full templating language.
 * Just use `kubectl` directly to install YAML. 
 * Traefik ingress controller. Traefik supports HTTP, HTTP(s) (with automatic
   ACME / Let's Encrypt certificate generation) and TCP. You can run SSH inside
   a container, and forward it through traefik!
 * Automatically downloads YAML templates from this git repository, all you need
   is a copy of [render.sh](render.sh) and the environment file containing your
   intended configuration.
   
Start by reading the [first post on the
blog](https://blog.rymcg.tech/blog/k3s/), in order to install k3s, traefik and
learn about `render.sh` and the environment files.
