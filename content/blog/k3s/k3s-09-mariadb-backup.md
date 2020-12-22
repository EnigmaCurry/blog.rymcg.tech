---
title: "K3s part 9: MariaDB backup"
date: "2020-12-11T00:09:00-06:00"
tags: ['k3s']
---

This post directly follows [part 8](/blog/k3s/k3s-08-wordpress) where you
installed Wordpress and MariaDB. To avoid disaster, you now need to schedule
backups of your database. You will modify the StatefulSet that runs MariaDB, so
as to start two additional containers (called sidecars) in the same pod, one
that performs a backup of the database to a new volume, and another to upload
the backup to offsite S3 storage via [Restic](https://restic.net/).

You will need to provide S3 compatible storage bucket, with access and secret
keys. You can use [DigitalOcean
Spaces](https://www.digitalocean.com/products/spaces/), AWS S3, Minio, CephFS,
etc.

## Config

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
NAMESPACE=wordpress
MARIADB_VERSION=10.4
BACKUP_VOLUME_SIZE=10Gi
```

Set your S3 bucket, endpoint, and credentials:

```env
RESTIC_BACKUP_IMAGE=lobaro/restic-backup-docker:1.3.1-0.9.6
MYSQL_BACKUP_IMAGE=woolfg/mysql-backup-sidecar:v0.3.1-mariadb-10.4
S3_BUCKET=your-bucket
S3_ENDPOINT=sfo2.digitaloceanspaces.com
S3_ACCESS_KEY_ID=xxxx
S3_SECRET_ACCESS_KEY=xxxx
```

## Generate Sealed Secret

Create a passphrase to encrypt the backups:

```bash
RESTIC_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
echo "SAVE THIS PASSWORD for restoring backups: ${RESTIC_PASSWORD}"
```

Copy the restic password someplace safe, you will need it, in case you need to
restore your backups later on a fresh cluster.

```bash
kubectl create secret generic mariadb-backups \
   --namespace ${NAMESPACE} --dry-run=client -o json \
   --from-literal=RESTIC_REPOSITORY=s3:https://${S3_ENDPOINT}/${S3_BUCKET} \
   --from-literal=RESTIC_PASSWORD=${RESTIC_PASSWORD} \
   --from-literal=S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID} \
   --from-literal=S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY} \
   | kubeseal -o yaml > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/mariadb-backups.sealed_secret.yaml
```

## Create Persistent Volume Claim for backups

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/mariadb-backups.pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-backups
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${BACKUP_VOLUME_SIZE}
  storageClassName: local-path
EOF
```

## Recreate MariaDB with sidecars for backup

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
              mountPath: /var/lib/mysql
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
        - name: mariadb-backups
          image: ${MYSQL_BACKUP_IMAGE}
          env:
            - name: CRON_SCHEDULE
              value: "30 2 * * *"
            - name: BACKUP_DIR
              value: /backup
            - name: INCREMENTAL
              value: "true"
            - name: MYSQL_HOST
              value: mariadb
            - name: MYSQL_USER
              value: root
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb
                  key: MARIADB_ROOT_PASSWORD
          volumeMounts:
            - name: mariadb
              mountPath: /var/lib/mysql
            - name: mariadb-backups
              mountPath: /backup
        - name: mariadb-s3-upload
          image: ${RESTIC_BACKUP_IMAGE}
          env:
            - name: RESTIC_REPOSITORY
              valueFrom:
                secretKeyRef:
                  name: mariadb-backups
                  key: RESTIC_REPOSITORY
            - name: RESTIC_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb-backups
                  key: RESTIC_PASSWORD
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: mariadb-backups
                  key: S3_ACCESS_KEY_ID
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: mariadb-backups
                  key: S3_SECRET_ACCESS_KEY
          volumeMounts:
            - name: mariadb-backups
              mountPath: /data
      volumes:
        - name: mariadb
          persistentVolumeClaim:
            claimName: mariadb
        - name: mariadb-backups
          persistentVolumeClaim:
            claimName: mariadb-backups
EOF
```

## Recreate kustomization.yaml

Recreate the kustomization.yaml so as to include the backups sealed secret and
PVC:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- mariadb.sealed_secret.yaml
- mariadb-backups.sealed_secret.yaml
- mariadb.pvc.yaml
- mariadb-backups.pvc.yaml
- mariadb.yaml
- wordpress.yaml
- wordpress.ingress.yaml
EOF
```

## Run the first backup

The backup job is scheduled via cron to occur at 02:30 (am), so you can kick off
the first backup job manually, rather than wait:

```bash
kubectl -n wordpress exec -it mariadb-0 -c mariadb-backups -- /scripts/backup.sh
```

The upload job is scheduled via cron to occur at 03:00 (am), so you can kick off the first upload job manually, rather than wait:

```bash
kubectl -n wordpress exec -it mariadb-0 -c mariadb-s3-upload -- /bin/backup
```

## In case you need to restore from S3 backup

```env
## Directory to restore to use (Use / if you want to overwrite existing /data)
RESTORE_ROOT=/restore-tmp
```

```bash
kubectl -n wordpress exec -it mariadb-0 -c mariadb-s3-upload -- mkdir ${RESTORE_ROOT}
kubectl -n wordpress exec -it mariadb-0 -c mariadb-s3-upload -- \
  restic restore --target ${RESTORE_ROOT} latest
```
