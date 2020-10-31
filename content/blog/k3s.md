---
title: "K3s"
url: "blog/k3s"
date: 2020-10-30T11:45:03-07:00
draft: true
tags: ['k3s']
---
## Abstract

 * Creates a single node [k3s](https://k3s.io) cluster on DigitalOcean for small
self-hosted apps and development.
 * Creates attached volume for pod storage.
 * Sets up DigitalOcean firewall.
 * Installs Traefik with automatic Lets Encrypt certificate generation. 
 * These same instructions can easily be adapted to Raspberry Pi or other raw
   metal.
 
This is considerably less expensive than hosted kubernetes solutions, like the
one DigitalOcean provides, as it does not incur the cost of the additonal Load
Balancer node (You can run all of this on a single $5 droplet). This makes it a
good fit for testing and for deployments where you don't care about high
availability (multi-node redundancy.)

## Deploy k3s

 * Create a Debian (`10 x64`) droplet on DigitalOcean
   * $10/mo 2GB RAM (tested configuration)
   * Add Block storage for pod volume storage
     * You choose how much space you need for all of your pods.
     * Choose `Manually Format & Mount` (we want to customize the mount point,
       so the following script will take care of formatting and mounting
       `/dev/sda` which is the device name for the volume you create.)
   * Enter the following script into the `User data` section of the droplet creation screen:
   
   ```bash
   #!/bin/bash
   mkfs.ext4 /dev/sda
   mkdir -p /var/lib/rancher/k3s/storage
   echo '/dev/sda /var/lib/rancher/k3s/storage ' \
        'ext4 defaults,nofail,discard 0 0' | sudo tee -a /etc/fstab
   mount /dev/sda
   apt-get update -y
   apt-get install -y curl
   ```
 * Assign your ssh key
 * Confirm details and create the droplet.
 * [Create a firewall](https://cloud.digitalocean.com/droplets/new):
 
   * Open TCP port 22 for SSH
   
   * Open TCP port 80 for unencrypted HTTP
   
   * Open TCP port 443 for TLS encrypted HTTPS
   
   * Open TCP port 6443 for Kubernetes (kubectl) access
   
   * **Apply the firewall to your droplet.**
   
 * Assign a [floating IP
   address](https://cloud.digitalocean.com/networking/floating_ips)
 * [Create wildcard DNS](https://cloud.digitalocean.com/networking/domains)
   names pointing to floating IP address (`example.com` and `*.example.com`)
 * Install kubectl on your workstation:
   * Prefer your os packages:
     * Arch: `sudo pacman -S kubectl`
     * Ubuntu and Other OS: [See docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-using-native-package-management)
 * Install k3sup on your workstation:
 
 ```bash
 curl -sLS https://get.k3sup.dev | sh
 sudo install k3sup /usr/local/bin/
 ```
 
 * Create the cluster using k3sup, replace `$IP_ADDRESS` with your droplet's
   floating IP address:
 
 ```bash
 mkdir -p ${HOME}/.kube
 k3sup install --ip $IP_ADDRESS --k3s-extra-args '--no-deploy traefik' \
     --local-path ${HOME}/.kube/config
 ```
 * Test kubectl (should print the node status as `Ready`)
 
 ```bash
 kubectl get node -o wide
 ```

## Deploy Traefik on k3s

Deployment files are included in the `src/k3s` directory which you can
clone from git:

```bash
DIR=$HOME/git/vendor/enigmacurry/blog.rymcg.tech
git clone https://github.com/EnigmaCurry/blog.rymcg.tech.git $DIR
cd $DIR/src/k3s
```

Make a copy of the included `prod-template` directory and call it `prod`:

```bash
cp -a prod-template/ prod
```

(`prod` is in the `.gitignore` file, so your changes in this directory are
not stored in git. If you wish to commit them, remove this line from
`.gitignore`)

The `prod` directory is now your directory to make configuration changes. 

Edit `prod/traefik/030-traefik-daemonset-patch.yaml`:

 * Choose the Lets Encrypt CA server for staging or prod. Use the
   `acme-staging-v02` until you are finished testing, but when you want to
   install permanently, change it to `acme-v02` to use the production Lets
   Encrypt server.
 * Edit your email address for Lets Encrypt certificates

Edit `prod/whoami/020-whoami-ingress-route-patch.yaml`:

 * Change the domain for the `whoami` ingress from `example.com` to match your
   domain.

Now apply the configuration to the cluster, using [kustomize](https://github.com/kubernetes-sigs/kustomize):

```bash
kubectl apply -k prod/traefik
```

If you get an error like `error: found conflict between different patches`,
you've encountered a bug in the bundled version of kustomize in kubectl, here is
the workaround:

Do this only if `kubectl apply -k` didn't work for you, which will download the
latest `kustomize` binary:

```bash
curl -s "https://raw.githubusercontent.com/\
kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
./kustomize build prod/traefik | kubectl apply -f -
```

Watch the traefik logs as it now starts up:

```bash
kubectl -n kube-system logs -f daemonset/traefik
```

(Press Ctrl-C anytime to quit watching the log, or it might be useful to keep
this running in a seperate terminal to see new log messages as they occur.)

Open your web broweser, and test that you can reach the whoami service at the
domain you chose. If using the staging Lets Encrypt server, the certificate
won't be valid, but verify that the certificate is issued by `Fake LE
Intermediate` to know if its working or not.

You can now deploy any other websites by copying the `prod/whoami` directory and
making modifications for your container images, and reapplying with `kubectl
apply -k` (or `kustomize`)
