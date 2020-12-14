---
title: "K3s part 6: Container registry"
date: 2020-12-11T00:06:00-06:00
tags: ['k3s']
---

If you can't access container images, you can't start containers. Self-hosting
your own cluster-local container registry is a must.

Configure the git repository directory you created in [part
1](/blog/k3s/k3s-01-setup) along with other config variables:

```env
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
REGISTRY_ADMIN=admin
REGISTRY_IMAGE=registry:2
REGISTRY_PVC_SIZE=20Gi
```

## Create namespace

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/registry && \
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: registry
EOF
```
## Generate passwords

```bash
gen_password() { head -c 16 /dev/urandom | sha256sum | cut -d " " -f 1; }
kube_run() {
    eval "kubectl run --quiet -i --rm --tty kube-run-${RANDOM} \
      --image=${1} --restart=Never -- ${@:2}"
}
htpasswd() {
    kube_run alpine /bin/sh -c \""apk add --no-cache apache2-utils \
      &> /dev/null && \
      htpasswd -Bbn ${1} ${2} | head -n 1 2> /dev/null\""
}
REGISTRY_PASSWORD=$(gen_password)
REGISTRY_AUTH=$(htpasswd ${REGISTRY_ADMIN} ${REGISTRY_PASSWORD})
REGISTRY_HTTP_SECRET=$(gen_password)
echo "-------------------------------"
echo REGISTRY_ADMIN is ${REGISTRY_ADMIN}
echo REGISTRY_PASSWORD is ${REGISTRY_PASSWORD}
echo REGISTRY_AUTH is ${REGISTRY_AUTH}
echo REGISTRY_HTTP_SECRET is ${REGISTRY_HTTP_SECRET}
```

## Create sealed secret

```bash
kubectl create secret generic registry \
   --namespace registry --dry-run=client -o json \
   --from-literal=REGISTRY_HTTP_SECRET=${REGISTRY_HTTP_SECRET} \
   --from-literal=REGISTRY_AUTH=${REGISTRY_AUTH} | kubeseal -o yaml > \
 ${FLUX_INFRA_DIR}/${CLUSTER}/registry/sealed_secret.yaml
```

## Create the config map

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: registry
  namespace: registry
data:
  config.yml: |
    version: 0.1
    log:
      fields:
        service: registry
    http:
      addr: :5000
      headers:
        X-Content-Type-Options: [nosniff]
    auth:
      htpasswd:
        realm: registry
        path: /auth/htpasswd
    storage:
      filesystem:
        rootdirectory: /var/lib/registry
      delete:
        enabled: true
    health:
      storagedriver:
        enabled: true
        interval: 10s
        threshold: 3
EOF
```

## Create the Physical Volume Claim

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  namespace: registry
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${REGISTRY_PVC_SIZE}
  storageClassName: local-path
EOF
```
## Create Service and Deployment

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/registry.yaml
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: registry
spec:
  ports:
  - name: web
    port: 5000
    protocol: TCP
  selector:
    app: registry
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: registry
  labels:
    app: registry
spec:
  selector:
    matchLabels:
      app: registry
  replicas: 1
  minReadySeconds: 5
  template:
    metadata:
      labels:
        app: registry
      annotations:
    spec:
      containers:
        - name: registry
          image: ${REGISTRY_IMAGE}
          ports:
            - containerPort: 5000
          livenessProbe:
            httpGet:
              path: /
              port: 5000
          readinessProbe:
            httpGet:
              path: /
              port: 5000
          resources:
          env:
            - name: REGISTRY_HTTP_SECRET
              valueFrom:
                secretKeyRef:
                  name: registry
                  key: REGISTRY_HTTP_SECRET
          volumeMounts:
            - name: registry-data
              mountPath: /var/lib/registry 
            - name: registry-auth
              mountPath: /auth
              readOnly: true
            - name: registry-config
              mountPath: "/etc/docker/registry"
      volumes:
        - name: registry-auth
          secret:
            secretName: registry
            items:
            - key: REGISTRY_AUTH
              path: htpasswd
        - name: registry-config
          configMap:
            name: registry
        - name: registry-data
          persistentVolumeClaim:
            claimName: registry-data
EOF
```

## Create Ingress

```bash
cat <<EOF | sed 's/@@@/`/g' > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: registry-web
  namespace: registry
spec:
  entryPoints:
  - websecure
  routes:
  - kind: Rule
    match: Host(@@@registry.${CLUSTER}@@@)
    services:
    - name: registry
      port: 5000
  tls:
    certResolver: default
EOF
```

## Create Kustomization

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/registry/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- sealed_secret.yaml
- config.yaml
- pvc.yaml
- registry.yaml
- ingress.yaml
EOF
```

## Commit manifests and push to deploy

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}/registry
git -C ${FLUX_INFRA_DIR} commit -m "registry"
```

```bash
git -C ${FLUX_INFRA_DIR} push origin master
```

## Configure cluster to use new registry

In order to configure the k3s cluster to login and use the registry, you need to
create file on the k3s host server:

```env
## The SSH host of the k3s server:
K3S_HOST=k3s.${CLUSTER}
```

```bash
cat <<EOF | ssh root@${K3S_HOST} tee /etc/rancher/k3s/registries.yaml
mirrors:
  registry.${CLUSTER}:
    endpoint:
      - "https://registry.${CLUSTER}"
configs:
  "registry.${CLUSTER}":
    auth:
      username: ${REGISTRY_ADMIN}
      password: ${REGISTRY_PASSWORD}
EOF
```

In order for this configuration to take effect, K3s must be restarted:

```bash
ssh root@${K3S_HOST} systemctl restart k3s
```

## Test cluster registry access

From your workstation, use `podman` (or `docker`) to login to the private
registry:

```bash
podman login registry.${CLUSTER} -u ${REGISTRY_ADMIN} -p ${REGISTRY_PASSWORD}
```

Pull the public `alpine` image to your workstation:

```bash
podman pull alpine
```

Tag the image and push to the private registry:

```bash
podman tag alpine registry.${CLUSTER}/alpine
podman push registry.${CLUSTER}/alpine
```


Create function to run interactive images:
```bash
kube_run() {
    eval "kubectl run --quiet -i --rm --tty kube-run-${RANDOM} \
      --image=${1} --restart=Never -- ${@:2}"
}
```

Run a test container, using the alpine image from docker.io:

```bash
kube_run alpine uname -a
```

You should see the container Linux kernel info printed.

Run the same image now from your private registry:

```bash
kube_run registry.${CLUSTER}/alpine uname -a
```

You should see the Linux kernel info printed again.
