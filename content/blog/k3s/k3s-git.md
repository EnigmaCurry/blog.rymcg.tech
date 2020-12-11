---
title: "K3s part 2: Git host"
date: 2020-12-09T14:04:24-07:00
tags: ['k3s']
---

## Create local git repository

You now have a fresh k3s cluster installed. Now you need a place to store your
configuration, so create a git repository someplace on your workstation called
`flux-infra` (or whatever you want to call it). The `flux-infra` repository will
manage one or more of your clusters. Each cluster storing its manifests in its
own sub-directory, listed by domain name. Each kubernetes namespace gets a
sub-sub-directory :
 * `~/git/flux-infra/${CLUSTER}/${NAMESPACE}` 
 
Choose the directory where to create the git repo and the domain name for your
new cluster:

```bash
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=flux.example.com
```

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER} && \
git -C ${FLUX_INFRA_DIR} init && \
cd ${FLUX_INFRA_DIR}/${CLUSTER} && \
echo Cluster working directory: $(pwd)
```

## Install Sealed Secrets

[bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets)
allows you to encrypt kubernetes secrets with a key secured by your cluster. You
can safely store sealed secrets in public (or private) git repositories.

You need to install the client `kubeseal` on your workstation, and you must
install the `sealed-secrets-controller` on your cluster.

If you are on Arch Linux, you can install `kubeseal` from the AUR. If you are on
a different platform, [follow the
directions](https://github.com/bitnami-labs/sealed-secrets/releases) for
installing the `Client side` only.

Find the latest version via curl:

```bash
SEALED_SECRET_VERSION=$(curl --silent \
  "https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest" | \
  grep -Po '"tag_name": "\K.*?(?=")')
echo Latest version: ${SEALED_SECRET_VERSION}
```
Now create the controller manifest, by making a `Kustomization` object in your
`kube-system` namespace:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system && \
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRET_VERSION}/controller.yaml
EOF
```

The Kustomization links the resource from the upstream project tagged to the
version.

Finally, install the controller:

```bash
kustomize build ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system | kubectl apply -f - 
```

## Create Secrets

Secrets include both individual strings, like passwords, and tokens, but also
entire files. For gitea, you need to store the following:

 * `POSTGRES_USER` - the username of the postgresql database user.
 * `POSTGRES_PASSWORD` - the password of the postgresql database user.
 * `INTERNAL_TOKEN` - gitea internal token
 * `JWT_SECRET` - gitea JWT secret
 * `SECRET_KEY` - gitea Secret key
 * gitea app.ini - the config file for gitea.

You will create new random generated passwords, store them as temporary
environment variables, then create the Sealed Secret, encrypting the values with
the cluster key into a new file.

Generate the secrets:

```bash
gen_password() { head -c 16 /dev/urandom | sha256sum | cut -d " " -f 1; }
POSTGRES_USER=gitea
POSTGRES_PASSWORD=$(gen_password)
INTERNAL_TOKEN=$(gen_password)
JWT_SECRET=$(gen_password)
SECRET_KEY=$(gen_password)
```

Create the plain text config file:
```bash
CONFIG_TMP=$(mktemp)
cat <<EOF > $CONFIG_TMP
APP_NAME = ${CLUSTER} git-system

[server]
DOMAIN = ${CLUSTER}
ROOT_URL = https://${CLUSTER}/
SSH_DOMAIN = ${CLUSTER}
SSH_PORT = 2222
START_SSH_SERVER = true

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true

[database]
DB_TYPE = postgres
NAME = ${POSTGRES_USER}
HOST = gitea-postgres
PASSWD = ${POSTGRES_PASSWORD}
USER = ${POSTGRES_USER}

[security]
INSTALL_LOCK = true
SECRET_KEY = ${SECRET_KEY}
INTERNAL_TOKEN = ${INTERNAL_TOKEN}
DISABLE_GIT_HOOKS = false

[oauth2]
JWT_SECRET = ${JWT_SECRET}
EOF
```

Create the Sealed Secret:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/git-system && \
kubectl create secret generic gitea \
   --namespace git-system --dry-run=client -o json \
   --from-literal=POSTGRES_USER=$POSTGRES_USER \
   --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
   --from-literal=INTERNAL_TOKEN=$INTERNAL_TOKEN \
   --from-literal=JWT_SECRET=$JWT_SECRET \
   --from-literal=SECRET_KEY=$SECRET_KEY \
   --from-file=app.ini=${CONFIG_TMP} | kubeseal -o yaml > \
 ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/sealed_secret.yaml
```

Destroy the evidence:

```bash
rm ${CONFIG_TMP}
unset POSTGRES_USER POSTGRES_PASSWORD INTERNAL_TOKEN JWT_SECRET SECRET_KEY
```

## Create namespace and manifest for gitea

Create two PhysicalVolumeClaims (`pvc`) to provision data volumes to store gitea
repository and postgresql data.

To create `namespace.yaml`:
```bash
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: git-system
EOF
```

To create `pvc.yaml`:
```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/git-system && \
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-postgres-data
  namespace: git-system
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: git-system
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
EOF
```

To create `database.yaml`

```bash
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/database.yaml
apiVersion: v1
kind: Service
metadata:
  name: gitea-postgres
  namespace: git-system
spec:
  selector:
    app: gitea-postgres
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitea-postgres
  namespace: git-system
spec:
  selector:
    matchLabels:
      app: gitea-postgres
  serviceName: gitea-postgres
  replicas: 1
  template:
    metadata:
      labels:
        app: gitea-postgres
    spec:
      containers:
        - name: gitea-postgres
          image: postgres
          volumeMounts:
            - name: gitea-postgres-data
              mountPath: /var/lib/postgresql/data
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: gitea
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gitea
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
      volumes:
        - name: gitea-postgres-data
          persistentVolumeClaim:
            claimName: gitea-postgres-data
EOF
```

To create `gitea.yaml`:
```bash
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/gitea.yaml
apiVersion: v1
kind: Service
metadata:
  name: gitea-web
  namespace: git-system
spec:
  ports:
  - name: web
    port: 80
    protocol: TCP
    targetPort: 3000
  selector:
    app: gitea
---
apiVersion: v1
kind: Service
metadata:
  name: gitea-ssh
  namespace: git-system
spec:
  ports:
  - name: ssh
    port: 2222
    targetPort: 2222
    protocol: TCP
  selector:
    app: gitea
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: gitea
  name: gitea
  namespace: git-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitea
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
      - image: gitea/gitea:latest
        name: gitea
        volumeMounts:
          - name: data
            mountPath: /data
          - name: config
            mountPath: /data/gitea/conf
        ports:
        - containerPort: 3000
          name: web
        - containerPort: 2222
          name: ssh
        env:
          - name: INSTALL_LOCK
            value: "true"
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitea-data
        - name: config
          secret:
            secretName: gitea
EOF
```

To create `kustomization.yaml`:

```bash
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- sealed_secret.yaml
- pvc.yaml
- database.yaml
- gitea.yaml
EOF
```

Apply the maniest to the cluster:

```bash
kustomize build ${FLUX_INFRA_DIR}/${CLUSTER}/git-system | kubectl apply -f - 
```
