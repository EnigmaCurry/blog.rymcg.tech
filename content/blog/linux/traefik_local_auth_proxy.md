---
title: "Traefik Local Auth Proxy"
date: 2026-01-28T12:54:00-06:00
tags: ['linux', 'traefik']
---

If you need to access an HTTP service that requires authorization
(`Bearer` or `Basic` auth), but you don't want to put the API token
anywhere near your code, you can use this script to create a
localhost-only proxy for that service. The proxy accepts
unauthenticated requests originating only from `127.0.0.1`, and it
will inject the API token into your requests, and forward them to the
upstream server.

This kind of thing might also be useful for integration with third
party software that doesn't support authentication. As a pilot case,
this script was designed for the integration of Ollama with Home
Assistant, but HA doesn't have an option to add a Bearer auth token
for Ollama. HA can now talk to the local proxy and the proxy injects
the API token into the request.

## Get the script

Download the script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/traefik/traefik_local_auth_proxy.sh
```

Make the script executable:

```bash
chmod a+x traefik_local_auth_proxy.sh
```

## Install Traefik

If you have [Nix](https://nixos.org/download/) installed, Traefik will
be installed automatically by the script. If not, [you can download
the latest binary of
Traefik](https://github.com/traefik/traefik/releases), and install it
in your PATH (e.g., `/usr/local/bin/traefik`).

## Examples

```bash
  # Run in foreground
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'abc123'
```

```bash
  # Install & enable as user service
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'abc123' \
    --install-user-service
```

```bash
  # Basic auth style header (example)
  ./traefik_local_auth_proxy.sh \
    --upstream https://api.example.com \
    --token 'dXNlcjpwYXNz' \
    --auth-header Authorization \
    --auth-prefix 'Basic' \
    --install-user-service
```

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/traefik/traefik_local_auth_proxy.sh)

{{< code file="/src/traefik/traefik_local_auth_proxy.sh" language="shell" >}}
