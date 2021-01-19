---
title: "Podman part 01: cloud-init as docker-compose alternative"
date: 2021-01-17T00:01:00-06:00
tags: ['podman']
draft: true
---

If you use containers for web-services, you're likely running one of two things:
docker (or docker-swarm) or kubernetes. For scale, and maximum description of
infrastructure, kubernetes is the better choice. For ease of bootstrapping one
single mininimally provisioned node, docker-compose really can't be beat. This
second scenario is the one I'm interested in for this series of posts. I don't
care about scale. I want fast deployment of one single, secure, server from
scratch, using minimal resources, easily maintained, and geared for light
production use. A "pet" server.

There is an alternative to Docker called Podman, which has the advantage of not
needing any running API daemon. With Podman, you can start containers as normal
processes. So this also means you can create containers directly from systemd,
as service units created in your host operating system (interact with
`systemctl` for start/stop/etc and `journalctl` to view logs, exactly like any
non-docker host service). Because there is no daemon running, it's one fewer
resource hogging the system (granted, docker is *much* less resource intensive
than kubernetes), one fewer dependency, and one less surface of attack.

But podman doesn't have a nice tool like docker-compose. Not yet at least,
[although it's being worked on for podman
3.0](https://www.redhat.com/sysadmin/podman-docker-compoes). Furthermore,
Trafeik can't talk to a docker API if that docker API doesn't exist (it will in
3.0), so you [can't use docker container labels for service discovery
(yet)](https://github.com/traefik/traefik/issues/5730).

OK. So podman can run containers as regular processes? (yes) And we can just
create regular systemd units to start containers? (yes) OK. We can just script
this in BASH pretty easy. So lets do it..

## Deploy a droplet

From cloud-init, (eg. the DigitalOcean `User data` option on the droplet
creation screen), you can provide this minimal script to bootstrap a node
(Ubuntu 20.04+) with podman, and two containers: one for `traefik`, and one for
`whoami`. Traefik will be a proxy for web traffic to all of the containers, as
well as perform TLS (https) encryption (with free Let's Encrypt certificate).
`whoami` is an example container that will respond to http, so that you can test
that the proxy (and certificate) works. Here's the script that you would paste
into the cloud-init `User data` text-area box:

```
#!/bin/bash
## App Config:
WHOAMI_DOMAIN=whoami.example.com
## Podman_Traefik Config:
ACME_EMAIL=you@example.com
ALL_CONFIGS=(whoami_config)
ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
PODMAN_TRAEFIK_SCRIPT=https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/cloud-init/podman_traefik.sh
########

whoami_config() {
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    TEMPLATES=(whoami_service)
    VARS=(WHOAMI_DOMAIN)
}
whoami_service() {
    local SERVICE=whoami
    local IMAGE=traefik/whoami
    local RANDOM_NAME=whoami-$(openssl rand -hex 3)
    local PODMAN_ARGS="--network web"
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" \
                             -port 8080 -name ${RANDOM_NAME}
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 8080
    systemctl enable ${SERVICE}
    systemctl restart ${SERVICE}
}
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)

```

Edit the config variables at the top, then finish creating the droplet. Create
wildcard DNS records for the domain (eg. `example.com` and `*.example.com`),
pointing to the droplet IP address (hint: use a Floating IP address, that way
you can re-create the droplet with ease, and not have to touch DNS again). Now
SSH to the droplet and run:

```
tail -f /var/log/cloud-init-output.log
```

You are watching the log of this script run on first bootup. It will say `All
done :)` at the end if it runs successfully. Press `Ctrl-C` to quit watching the
log.

At the end of all this, you should now be able to open your web browser to
https://whoami.example.com (or whatever domain you chose.) and see the debug
text from the whoami service. If you went with the default staging `ACME_CA`,
you will instead be greeted with an error about the certificate being invalid.
This is expected behaviour until you use the production Lets Encrypt `ACME_CA`;
if you check the certificate in the URL bar, it will be issued by `Fake LE
Intermediate` authority; confirm the exception in your browser, and you should
still be able to visit the whoami page anyway. If you used the production
`ACME_CA`, you should see a valid certificate from `Let's Encrypt Authority`,
and see the whoami output right away.

You can add additional containers following this same format. For a new app
called `demo` you would create two new functions:

 * `demo_config` following the example of `whoami_config`.
 * `demo_service` following the example of `demo_service`.

Append the new configs to `ALL_CONFIGS`:

```
ALL_CONFIGS=(whoami_config demo_config)
```

That's it! 

Read on, only to find out more about how this works on the inside.

Stay tuned for future blog posts in this series, that will give a larger
example, like with databases and such.

## Description of whats happening

The variables at the top of the script are for you to customize before Droplet
creation. I usually would just copy and paste the whole script into the Droplet
creation screen (`User data` field), and edit it right there.

The script imports another script to do the traefik config
[podman_traefik.sh](https://github.com/EnigmaCurry/blog.rymcg.tech/blob/master/src/cloud-init/podman_traefik.sh),
(this helps keep the current script smaller and more to the point: "I just want
the whoami service, please."). The podman_traefik script performs all the steps
for installing podman and traefik behind the scenes. The calling script just has
to define the `whoami` service, and provide some configuration variables.

The podman_traefik script expects several environment variables to be defined in
the caller script:

 * `ACME_EMAIL` - this is your email address that you want to register with
   Let's Encrypt. (it must be real. example.com will NOT work with the
   production Let's Encrypt service.)
 * `ACME_CA` - this is the URL to the Let's Encrypt Certificate Authority API (or
   your own ACME server, like [Step CA](https://smallstep.com/docs/step-ca)). By
   default this is set to the *staging* Let's Encrypt environment. This is quite
   useful for testing when you need to re-deploy the entire server several times
   in a row. This is because the production environment has a rate-limit on the
   number of certifacates you can generate. In order to generate public valid TLS
   certificates, you must use the production service. To use the production
   service, set `ACME_CA=https://acme-v02.api.letsencrypt.org/directory` (its
   the same URL minus the `-staging` part.) You should only use production once
   you have tested everything works correctly on staging, first.
 * `ALL_CONFIGS` - this is the list of all of the (bash) functions that need to be
   called by the podman_traefik script that sets up your deployments. In this
   example, we only have one deployment, so `ALL_CONFIGS=(whoami_config)`, but you can
   add to this list if you add more later, for example:

```
ALL_CONFIGS=(whoami_config postgres_config app1_config app2_config)
```

 * `BASE_PODMAN_ARGS` (optional) - this is the minimal list of podman arguments
   that all containers are given. By default this is `-l podman_traefik
   --cap-drop ALL`, which sets a label, and drops all system privileges. In each
   individual service, you should add back the privileges that you need, by
   setting `--cap-add NAME` ([see what you might need
   here](https://opensource.com/business/15/3/docker-security-tuning)). This way
   each container only has the privileges it really needs. Note
   `BASE_PODMAN_ARGS` must not be blank, so at least leave the label.

The rest of the variables in the script are just helpers for the local script,
they are not required for podman_traefik use, but help configure the `whoami`
service config function:

 * `WHOAMI_DOMAIN` - this is the domain name you want to let the `whoami`
   service respond to, exposing it to the public internet. You need to have
   setup a DNS record (type `A`) that points this domain to your server's IP
   address. Traefik will do the reverse-proxy for this service domain, and
   automatically redirect HTTP port 80 to HTTPs port 443, and automatically
   renew TLS certificates for this domain.
 
 * `PODMAN_TRAEFIK_SCRIPT` - this is the URL to import the `podman_traefik`
   script from. You could fork this repository, modify the script, and set your
   own URL.

Because you set `ALL_CONFIGS=(whoami_config)` in the script, (listing the one
function needed to configure the whoami service) the `podman_traefik` script
will later on, know to call the function called `whoami_config` to setup the
whoami config variables:

```
## This function is called by podman_traefik 
## because its listed in ALL_CONFIGS:
whoami_config() {
    # This is the DEFAULT (example) domain to use. 
    # All config variables require a DEFAULT value, even if its just used as an example.
    DEFAULT_WHOAMI_DOMAIN=whoami.example.com
    # The list of all the template functions:
    TEMPLATES=(whoami_service)
    # The list of all the config variables (all having a DEFAULT above)
    # A caller script may define these variables to override the defaults:
    VARS=(WHOAMI_DOMAIN)
}
```

The `whoami_config` function (and all other config functions you write) sets up
the following:

 * Default values for all of config variables. (Every config variable requires a
   default, even if it wouldn't work as-is, but serves as an example.)
 * The names of the template functions (`TEMPLATES`) to run in order to
   configure the service.
 * All of the variable names to pass to the templates (`VARS`). (Always without
   the `DEFAULT_` prefix.)

This example set `TEMPLATES=(whoami_service)`, having one template function to
run, called `whoami_service`:

```
whoami_service() {
    # These variables are all local, and just for descriptive purposes:
    # SERVICE is the name of the container to create
    local SERVICE=whoami
    
    # IMAGE is the docker container image name/tag
    local IMAGE=traefik/whoami
    
    # Just a random string to pass to the whoami container command arguments:
    local RANDOM_NAME=whoami-$(openssl rand -hex 3)

    # Give additional arguments to the `podman run` command:
    # Tell podman to create this container in the `web` network, 
    #   this is so that traefik can proxy it. 
    # You can also map ports or mount volumes here (`-p` or `-v` etc):
    local PODMAN_ARGS="--network web"
    
    # create_service_container is a function from the podman_traefik script.
    # This will create the Systemd Unit file and start the container:
    # 3+ arguments: SERVICE IMAGE "PODMAN_ARGS" [COMMAND_ARGS ...]
    create_service_container ${SERVICE} ${IMAGE} "${PODMAN_ARGS}" \
        -name ${RANDOM_NAME}
    
    # create_service_proxy is a function from the podman_traefik script.
    # This will create a traefik config to proxy this service.
    # 3 arguments: SERVICE DOMAIN PORT
    create_service_proxy ${SERVICE} ${WHOAMI_DOMAIN} 80
    
    # start the systemd service now, and configure to start on system boot:
    systemctl enable --now ${SERVICE}
}
```

Finally, the `podman_traefik` script is retrieved from the URL, and run:

```
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)
```

Which passes all of the variables and functions defined so far to the script,
which it will use to install podman, setup traefik, and call your template
functions to create additional containers.

## Description of the podman_traefik script

If you're satisfied with the black box description so far, you don't really have
to understand the inside details of
[podman_traefik.sh](https://github.com/EnigmaCurry/blog.rymcg.tech/blob/master/src/cloud-init/podman_traefik.sh)
to make use of it. But lets describe the details of it in case you're curious:

The script ran in cloud-init referenced two functions defined in podman_traefik:
`create_service_container` and `create_service_proxy`. These are template
functions to create config files for systemd and traefik, respectively.

```
create_service_container() {
    ## Template function to create a systemd unit for a podman container
    ## Expects environment file at /etc/sysconfig/${SERVICE}
    SERVICE=$1
    IMAGE=$2
    PODMAN_ARGS="-l podman_traefik $3"
    CMD_ARGS=${@:4}
    touch /etc/sysconfig/${SERVICE}
    cat <<EOF > /etc/systemd/system/${SERVICE}.service
[Unit]
After=network-online.target

[Service]
ExecStartPre=-/usr/bin/podman rm -f ${SERVICE}
ExecStart=/usr/bin/podman run --name ${SERVICE} --rm --env-file /etc/sysconfig/${SERVICE} ${PODMAN_ARGS} ${IMAGE} ${CMD_ARGS}
ExecStop=/usr/bin/podman stop ${SERVICE}
SyslogIdentifier=${SERVICE}
Restart=always

[Install]
WantedBy=network-online.target
EOF
}
```

The job of `create_service_container` is to create a file in
`/etc/systemd/system` that is a systemd unit file for running the container with
podman. Its a lot of boilerplate, but the important bit is the line that starts
with `ExecStart`, this is the command that runs podman and sends all of the
config variables to the container and passes additional podman arguments for
network or volume configs.

```
create_service_proxy() {
    ## Template function to create a traefik configuration for a service.
    ## Creates automatic http to https redirect.
    ## Note: traefik will automatically reload configuration when the file changes.
    TRAEFIK_SERVICE=traefik
    SERVICE=$1
    DOMAIN=$2
    PORT=${3:-80}
    cat <<END_PROXY_CONF > /etc/sysconfig/${TRAEFIK_SERVICE}.d/${SERVICE}.toml
[http.routers.${SERVICE}]
  entrypoints = "web"
  rule = "Host(\"${DOMAIN}\")"
  middlewares = "${SERVICE}-secure-redirect"
[http.middlewares.${SERVICE}-secure-redirect.redirectscheme]
  scheme = "https"
  permanent = "true"
[http.routers.${SERVICE}-secure]
  entrypoints = "websecure"
  rule = "Host(\"${DOMAIN}\")"
  service = "${SERVICE}"
  [http.routers.${SERVICE}-secure.tls]
    certresolver = "default"
[[http.services.${SERVICE}.loadBalancer.servers]]
  url = "http://${SERVICE}:${PORT}/"
END_PROXY_CONF
}
```

The job of `create_service_proxy` is to create a file in
`/etc/sysconfig/traefik.d/whoami.toml` (or other appropriate name for your
service.) This is the Traefik config file for this service. Traefik is
configured to find any config file written to this directory and load it
automatically. The arguments are three: `SERVICE DOMAIN PORT` for example
`create_service_proxy whoami whoami.example.com 80`. This makes Traefik forward
incoming HTTPs 443 that matches the domain name `whoami.example.com`, and direct
it to the whoami service on port 80. The service will acquire a certificate from
the `default` certresolver, which will be configured for Let's Encrypt.

The rest of the podman_traefik script consists of a single large function called
`wrapper`. The wrapper's job is to apply the merging of the DEFAULT variable
values with the provided variables from the caller script's environment, as well
as to create a new script installed permanently on the system that records the
the discovered cofniguration as hard-coded values. This permanent script lives
on the server and and can be edited and re-run to re-configure.

Inside the `wrapper` script are these functions:

 * `core_config` - This is the core traefik configuration. It follows the same
   format as that of the `whoami_config` you used before:
   
   1. Declare DEFAULT variables and their values.
   2. Create list of all the template functions (`TEMPLATES`).
   3. Create list of all the template variables (`VARS`).

 * `traefik_service` - This is the traefik template function. It follows the
   same format as that of the `whoami_service` you used before:
   
   1. Declare local descriptive variables (`SERVICE IMAGE NETWORK_ARGS VOLUME_ARGS`)
   2. Call `create_service_container` to create the systemd unit file.
   3. Create traefik config file (since this is the main traefik config, it
      doesn't call `create_service_proxy`)
   4. Call `systemctl enable --now ${SERVICE}` to start the container.
 
 * `merge_config` does the job of merging the DEFAULT and environment provided config.
 * `create_script` does the job of creating the permanently installed script
   `SCRIPT_INSTALL_PATH=/usr/local/sbin/podman_traefik.sh` and hard-coding the
   config into this file.
   
Note that the podman_traefik script does not run anything by default, it only
defines functions. So it must be sourced and run in a calling environment:

```
(
    set -euxo pipefail
    source <(curl -L ${PODMAN_TRAEFIK_SCRIPT})
    wrapper
)

```

