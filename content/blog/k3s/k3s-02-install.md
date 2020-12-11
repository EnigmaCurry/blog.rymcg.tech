---
title: "K3s part 2: Creating a cluster"
date: 2020-12-11T00:02:00-06:00
tags: ['k3s']
draft: true
---

## Create Droplet

 * Create a Debian (`10 x64`) droplet on DigitalOcean
   * $10/mo 2GB RAM (tested configuration).
   * Optional: Add a block storage volume for pod data.
     * You choose how much space you need for all of your pods.
     * If you don't add a volume, pod storage will live on the root filesystem
       of the droplet. (`/var/lib/rancher/k3s/storage`)
   * Enter the following script into the `User data` section of the droplet
     creation screen:
   
   ```bash
   #!/bin/bash
   VOLUME=/dev/sda
   mkdir -p /var/lib/rancher/k3s/storage
   umount ${VOLUME}
   if (blkid ${VOLUME}); then 
     yes | mkfs.ext4 ${VOLUME}
     echo "${VOLUME} /var/lib/rancher/k3s/storage " \
          "ext4 defaults,nofail,discard 0 0" | sudo tee /etc/fstab
     mount ${VOLUME}
   fi
   apt-get update -y
   apt-get install -y curl ufw
   
   ## UFW firewall rules
   ufw allow 22/tcp
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw allow 6443/tcp
   ufw allow 2222/tcp
   ufw enable
   systemctl enable --now ufw

   ## k3s install
   curl -sfL https://get.k3s.io | sh -s - server --disable traefik
   cat /etc/rancher/k3s/k3s.yaml | \
     sed "s/127.0.0.1/$(hostname -I | cut -d ' ' -f 1)/g" \
       > /etc/rancher/k3s/k3s.external.yaml && \
     chmod 0600 /etc/rancher/k3s/k3s.external.yaml
   ```

 * Assign your workstation's ssh client key to the droplet, to allow remote
   management.
   
 * Configure a hostname, like `k3s-flux`.
   
 * Confirm the details and finalize the droplet creation.
   
 * Assign a [floating IP
   address](https://cloud.digitalocean.com/networking/floating_ips)
   
 * [Create wildcard DNS](https://cloud.digitalocean.com/networking/domains)
   names pointing to floating IP address (`*.subdomain.example.com`)
   
## Download cluster API key

To access the cluster from your workstation, you must download the API key from
the k3s server. Set a temporary variable for the the floating IP address of the
server, and the desired path to store the cluster key.

```bash
FLOATING_IP=X.X.X.X
export KUBECONFIG=${HOME}/.kube/config
```

Download the key from the cluster, while replacing the correct IP address for
remote access:

```bash
ssh ${FLOATING_IP} -l root -o StrictHostKeyChecking=no \
  cat /etc/rancher/k3s/k3s.external.yaml > ${KUBECONFIG}
```

 * Test kubectl access with the key:
 
 ```bash
 kubectl get node -o wide
 ```
(It should print the node status as `Ready` once k3s finishes initialization. The name of the node displayed, should be the same hostname you created on the droplet page.)

If you set `KUBECONFIG` to anything other than the default
(`$HOME/.kube/config`) you should add `export KUBECONFIG=...` into your
`~/.bashrc` file, so that kubectl remembers which cluster config to use.

