---
title: "K3s part 3: Install Flux"
date: 2020-12-09T14:04:24-08:00
tags: ['k3s']
---

## Install flux command line tool

Follow the docs to [Install
flux2](https://github.com/fluxcd/flux2/tree/main/install) (On Arch Linux, you
may install `flux-go` from the AUR.)

Add shell completion support to your `~/.bashrc`

```bash
## ~/.bashrc
. <(flux completion bash)
```

## Create infrastructure repository

Create a new git repository on your git host called `flux-infra` (or whatever
you want). Create temporary variables to set the SSH clone URL, and the local
git directory.

```bash
FLUX_INFRA_REPO=ssh://git@git.example.com:22/username/flux-infra.git
FLUX_INFRA_DIR=${HOME}/git/flux-infra
```

The `flux-infra` repository is used to manage several clusters, with each having
its own subdirectory. Define the name of the initial cluster to setup:

```bash
CLUSTER=flux.example.com
```

Clone the repository to your workstation:

```bash
git clone ${FLUX_INFRA_REPO} ${FLUX_INFRA_DIR}
mkdir ${FLUX_INFRA_DIR}/${CLUSTER}
cd ${FLUX_INFRA_DIR}/${CLUSTER}
```

## Install flux operators

Create the YAML manifests for flux:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system
flux install --version=latest --arch=amd64 --export > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/gotk-components.yaml
```

Examine the gotk-components.yaml file, then apply to the cluster:

```bash
kubectl apply -f ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/gotk-components.yaml
```

Verify running pods:

```bash
kubectl get pods -n flux-system
```
Example output:

```
NAME                                       READY   STATUS    RESTARTS   AGE
source-controller-7c7b47f5f-ntlv6          1/1     Running   0          39s
helm-controller-6b9979865b-4vdff           1/1     Running   0          36s
notification-controller-596664f5f9-qt6jj   1/1     Running   0          31s
kustomize-controller-79948786c9-k4bzt      1/1     Running   0          38s
```

Commit and push the manifest to the remote git repository:

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "init ${CLUSTER} flux-system"
git -C ${FLUX_INFRA_DIR} push
```


## Watch the infrastructure repository for changes

In the last step, we used `kubectl apply` to manually apply the manifest to the
cluster. From now on, we'd like flux to monitor changes to the git repository,
and apply the manifests automatically.

The flux `GitRepository` object defines the remote repository to peridoically
pull and watch for changes. Create this for the flux-infra repo:

```bash
flux create source git flux-system \
  --url=${FLUX_INFRA_REPO} \
  --ssh-key-algorithm=rsa \
  --ssh-rsa-bits=4096 \
  --branch=master \
  --interval=1m
```

**This will output a public SSH key, which will be used to login to your remote
git repository. You must copy the key and install it as a Deploy Key in the
remote git repository settings. In github/gitea add the deploy key under
repository `Settings->Deploy Keys`. The deploy key does not require write
privileges. Once installed, press `Y` and Enter to continue.**

The `Kustomization` object defines a job to apply the source code downloaded
from a `GitRepository`, and apply it to the cluster. Create this for the
flux-infra repo:

```bash
flux create kustomization flux-system \
  --source=flux-system \
  --path="./${CLUSTER}" \
  --prune=true \
  --interval=10m
```

Export configuration manifests:

```bash
flux export source git flux-system > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/gotk-sync.yaml
flux export kustomization flux-system >> \
  ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/gotk-sync.yaml
```

Create the kustomization.yaml file that lists all manifests to apply:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
EOF
```

Commit and push the changes to the remote git repository:

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} flux-system"
git -C ${FLUX_INFRA_DIR} push
```

If you add new manifests, make sure to edit `kustomization.yaml` to list them.
Whenever you commit and push changes, the `Kustomization` job will automatically
apply them.

## Test it

Create a new manifest to create a namespace called `tmp-namespace` just for
testing.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/tmp-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tmp-namespace
EOF
```

Recreate the kustomization now with three manifests, including the tmp-namespace:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
- tmp-namespace.yaml
EOF
```

Commit and push the changes to the remote git repository:

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} flux-system"
git -C ${FLUX_INFRA_DIR} push
```

Within one minute, you should see the new `tmp-namespace` namespace.

```bash
# kubectl get ns tmp-namespace
NAME            STATUS   AGE
tmp-namespace   Active   20s
```

Now recreate the kustomization back to what it was, without the `tmp-namespace`
manifest:


```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
EOF
```

Commit and push the changes to the remote git repository:

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} flux-system"
git -C ${FLUX_INFRA_DIR} push
```

In about another minute, the namespace will be gone:

```bash
# kubectl get ns tmp-namespace
Error from server (NotFound): namespaces "tmp-namespace" not found
```


