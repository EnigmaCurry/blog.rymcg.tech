---
title: "k3s part3: Volume Backups"
url: "blog/longhorn"
date: 2020-11-30T20:04:03-07:00
tags: ['k3s', 'kubernetes']
draft: true
---
## Abstract

 * This is part 3 of the [k3s](/tags/k3s/) series. 
 * You will install [Longhorn](https://longhorn.io/docs/1.0.2/what-is-longhorn/)
   to act as a CSI compliant volume store on your k3s cluster.
 * You will install [velero](https://github.com/vmware-tanzu/velero) to create
   snapshots of volumes and backup to DigitalOcean volumes.
 
## Longhorn

You can read the [longhorn install guide for
k3s](https://longhorn.io/docs/1.0.2/advanced-resources/os-distro-specific/csi-on-k3s/)
or you can just do this as described here:

Install open-iscsi package on the k3s host:

```bash
apt install open-iscsi
```

Install longhorn:

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
```

Watch for the install to finish:

```bash
kubectl get pods \
--namespace longhorn-system \
--watch
```

DOESNT WORK
