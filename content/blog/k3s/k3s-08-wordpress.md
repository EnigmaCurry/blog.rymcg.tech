---
title: "K3s part 8: Wordpress. Or: Running stateful and stateless containers "
date: 2020-12-11T00:08:00-06:00
tags: ['k3s']
---

The blog you're reading is static, built using [hugo](https://gohugo.io/). I
personally don't have any use for Wordpress, but it is a ubiquitous application
which is useful for demonstrating a simple installation.

You can see from the [Wordpress docker-compose
quickstart](https://docs.docker.com/compose/wordpress/), the installation only
requires two containers: MariaDB, and Wordpress itself. MariaDB is stateful, it
requires a volume to store data. Wordpress is stateless, it only needs to talk
to a database. In kubernetes, stateful apps can be created with
[StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
and stateless apps can be created with
[Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

## Config

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
NAMESPACE=wordpress
MARIADB_VOLUME_SIZE=5Gi
MARIADB_VERSION=10.4
```

## Create wordpress namespace 

Create a new directory for the wordpress namespace and manifests, and create
`kustomization.yaml` which will list all of the manifest files to be created.

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- mariadb.sealed_secret.yaml
- mariadb.pvc.yaml
- mariadb.yaml
- wordpress.yaml
- wordpress.ingress.yaml
EOF
```

Create the namespace:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
```

## Create the Sealed Secret

MariaDB requires a database name, root password, and regular username and password,
which will all be stored in a Secret.

```bash
MARIADB_DATABASE=wordpress
MARIADB_ROOT_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
MARIADB_USER=wordpress
MARIADB_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
```

```bash
kubectl create secret generic mariadb \
   --namespace ${NAMESPACE} --dry-run=client -o json \
   --from-literal=MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD} \
   --from-literal=MARIADB_DATABASE=${MARIADB_DATABASE} \
   --from-literal=MARIADB_USER=${MARIADB_USER} \
   --from-literal=MARIADB_PASSWORD=${MARIADB_PASSWORD} | kubeseal -o yaml > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/mariadb.sealed_secret.yaml
```

## Create the MariaDB PersistentVolumeClaim

The
[PersistentVolumeClaim](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
will provision a volume to store data for MariaDB.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/mariadb.pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${MARIADB_VOLUME_SIZE}
  storageClassName: local-path
EOF
```

## Create the MariaDB Database

A
[StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
is used to deploy MariaDB since it stores its state into a volume. The
configuration references the secrets stored in the mariadb sealed secret:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/mariadb.yaml
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  namespace: ${NAMESPACE}
spec:
  selector:
    app: mariadb
  type: ClusterIP
  ports:
    - port: 3306
      targetPort: 3306
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: mariadb
  serviceName: mariadb
  replicas: 1
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
        - name: mariadb
          image: mariadb:${MARIADB_VERSION}
          volumeMounts:
            - name: mariadb
              mountPath: /var/lib/mariadb
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb
                  key: MARIADB_ROOT_PASSWORD
            - name: MYSQL_DATABASE
              valueFrom:
                secretKeyRef:
                  name: mariadb
                  key: MARIADB_DATABASE
            - name: MYSQL_USER
              valueFrom:
                secretKeyRef:
                  name: mariadb
                  key: MARIADB_USER
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb
                  key: MARIADB_PASSWORD
      volumes:
        - name: mariadb
          persistentVolumeClaim:
            claimName: mariadb
EOF
```

## Create Wordpress service

A
[Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
is used to deploy wordpress, since it does not have state (and no attached
volume)

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/wordpress.yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: ${NAMESPACE}
spec:
  ports:
  - name: web
    port: 80
  selector:
    app: wordpress
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: wordpress
  name: wordpress
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - image: wordpress:latest
        name: wordpress
        ports:
        - containerPort: 80
          name: web
        env:
        - name: WORDPRESS_DB_HOST
          value: mariadb:3306
        - name: WORDPRESS_DB_NAME
          valueFrom:
            secretKeyRef:
              name: mariadb
              key: MARIADB_DATABASE
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: mariadb
              key: MARIADB_USER
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mariadb
              key: MARIADB_PASSWORD
EOF
```

## Create Wordpress IngressRoute

The
[IngressRoute](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-ingressroute)
will expose wordpress to the public network outside the cluster.

```bash
cat <<EOF | sed 's/@@@/`/g' > \
   ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/wordpress.ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: wordpress
  namespace: ${NAMESPACE}
spec:
  entryPoints:
  - websecure
  routes:
  - kind: Rule
    match: Host(@@@wordpress.${CLUSTER}@@@)
    services:
    - name: wordpress
      port: 80
  tls:
    certResolver: default
EOF
```

## Commit and push new files

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} ${NAMESPACE}"
```

```bash
git -C ${FLUX_INFRA_DIR} push
```

## Test it

Your new wordpress blog is at https://wordpress.k3s.example.com

## Check logs

Mariadb logs: 

```bash
kubectl -n wordpress logs statefulset/mariadb
```

Wordpress logs:

```bash
kubectl -n wordpress logs deployment/wordpress
```

Kustomize: 

```bash
kubectl -n flux-system logs deployment/kustomize-controller
```
