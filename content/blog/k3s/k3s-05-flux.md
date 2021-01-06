---
title: "K3s part 5: Flux GitOps"
date: 2020-12-11T00:05:00-06:00
tags: ['k3s']
---

[Flux](https://fluxcd.io/) is a Continuous Delivery platform for Kubernetes
infrastructure. Flux will syncrhonize your git repository containing your YAML
manifests, and automatically apply changes to your cluster. Manage your cluster
via GitOps!

## Install flux operators

Configure the git repository directory you created in [part
1](/blog/k3s/k3s-01-setup) along with other config variables:

```env
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
GITEA_USER=root
GIT_REMOTE=ssh://git@git.${CLUSTER}:2222/${GITEA_USER}/flux-infra.git
```

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
```

```bash
git -C ${FLUX_INFRA_DIR} push
```


## Watch the infrastructure repository for changes

In the last step, we used `kubectl apply` to manually apply the manifest to the
cluster. From now on, we'd like flux to monitor changes to the git repository,
and apply the manifests automatically.

The flux `GitRepository` object defines the remote repository to peridoically
pull and watch for changes. Create this for the flux-infra repo:

```bash
flux create source git flux-infra \
  --url=${GIT_REMOTE} \
  --ssh-key-algorithm=rsa \
  --ssh-rsa-bits=4096 \
  --branch=master \
  --interval=1m
```

**This will output a public SSH key, which will be used to login to your remote
git repository. You must copy the key and install it as a Deploy Key in the
remote git repository settings. In Gitea add the deploy key under the repository
`Settings->Deploy Keys`. The deploy key does not require write privileges. Once
installed, press `Y` and Enter to continue.**

The `Kustomization` object defines a job to apply the source code downloaded
from a `GitRepository`, and apply it to the cluster. Create this for the
flux-infra repo:

```bash
flux create kustomization ${CLUSTER} \
  --source=flux-infra \
  --path="./${CLUSTER}" \
  --prune=true \
  --interval=10m
```

Export configuration manifests:

```bash
flux export source git flux-infra > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/gotk-sync.yaml
flux export kustomization ${CLUSTER} >> \
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
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER}"
```
```bash
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

```
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


## Logs

To check the kustomize logs:

```bash
kubectl -n flux-system logs deployment/kustomize-controller
```
