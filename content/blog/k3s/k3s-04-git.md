---
title: "K3s part 4: Git host"
date: 2020-12-11T00:04:00-06:00
tags: ['k3s']
---

[Gitea](https://gitea.io/) is a self-hosted git platform, much like GitHub. You
will push your local `flux-infra` git repository to gitea, for backup, and for
continuous delivery (CD) via Flux (Flux to be installed in [part
5](/blog/k3s/k3s-05-flux).

Configure the git repository directory you created in [part
1](/blog/k3s/k3s-01-setup) along with other config variables:

```env
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
```


## Install Sealed Secrets

[bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets)
allows you to encrypt and decrypt kubernetes secrets, with a key secured by your
cluster. You can safely store the sealed secrets in public (or private) git
repositories.

Sealed Secrets require a client tool (`kubeseal`) on your workstation, and a
kubernetes controller installed on the server. You already installed `kubeseal`
in [part1](/blog/k3s/k3s-01-setup), and now you will install the kubernetes
controller:

```env
SEALED_SECRET_VERSION=v0.13.1
```
Append the sealed secret manifest to the existing `kustomization.yaml` file:

```bash
cat <<EOF >> ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/kustomization.yaml
- https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRET_VERSION}/controller.yaml
EOF
```

The Kustomization links the resource from the upstream project tagged to the
version.

Apply to the cluster:

```bash
kustomize build ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system | kubectl apply -f - 
```

## Create Secrets

Secrets include strings, like passwords, and tokens, but also entire files.
Authorized pods can access secrets as an environment variable, and/or like a
file mounted to a path. For gitea, you need to store the following:

 * `POSTGRES_USER` - the username of the postgresql database user.
 * `POSTGRES_PASSWORD` - the password of the postgresql database user.
 * `INTERNAL_TOKEN` - gitea internal token
 * `JWT_SECRET` - gitea JWT secret
 * `SECRET_KEY` - gitea Secret key
 * gitea's `app.ini` - the config file for gitea.

Generate passwords and tokens:

```bash
POSTGRES_USER=gitea
POSTGRES_PASSWORD=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
INTERNAL_TOKEN=$(eval "kubectl run --quiet -i --rm gen-passwd-${RANDOM} \
   --image=gitea/gitea:latest --restart=Never -- \
   gitea generate secret INTERNAL_TOKEN")
SECRET_KEY=$(eval "kubectl run --quiet -i --rm gen-passwd-${RANDOM} \
   --image=gitea/gitea:latest --restart=Never -- \
   gitea generate secret SECRET_KEY")
JWT_SECRET=$(eval "kubectl run --quiet -i --rm gen-passwd-${RANDOM} \
   --image=gitea/gitea:latest --restart=Never -- \
   gitea generate secret JWT_SECRET")
echo Generated POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
echo Generated INTERNAL_TOKEN=${INTERNAL_TOKEN}
echo Generated SECRET_KEY=${SECRET_KEY}
echo Generated JWT_SECRET=${JWT_SECRET}
```

(You may see a warning message : `Error attaching, falling back to logs`. Its
harmless, just check to see if each variable has set a random string value as
echoed in the output.)


Create the plain text config file:
```bash
CONFIG_TMP=$(mktemp)
cat <<EOF > $CONFIG_TMP
APP_NAME = git.${CLUSTER}

[server]
DOMAIN = git.${CLUSTER}
ROOT_URL = https://git.${CLUSTER}/
SSH_DOMAIN = git.${CLUSTER}
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

[repository]
DEFAULT_PRIVATE = private

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

## Install Gitea

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
kind: StatefulSet
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
  serviceName: gitea-web
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
      - image: gitea/gitea:latest
        name: gitea
        ## debug:
        ## command: ["/bin/sh", "-c", "sleep 99999999999"]
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

To create `ingress.yaml`, which creates the IngressRoute to route gitea through
the Traefik proxy to the public internet:

```bash
cat <<EOF | sed 's/@@@/`/g' > ${FLUX_INFRA_DIR}/${CLUSTER}/git-system/ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: TraefikService
metadata:
  name: gitea-ssh
  namespace: git-system

spec:
  weighted:
    services:
      - name: gitea-ssh
        weight: 1
        port: 2222

---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: gitea-web
  namespace: git-system
spec:
  entryPoints:
  - websecure
  routes:
  - kind: Rule
    match: Host(@@@git.${CLUSTER}@@@)
    services:
    - name: gitea-web
      port: 80
  tls:
    certResolver: default
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRouteTCP
metadata:
  name: gitea-ssh
  namespace: git-system
spec:
  entryPoints:
  - ssh
  routes:
  - kind: Rule
    ## Domain matching is not possible with SSH, so match all domains:
    match: HostSNI(@@@*@@@)
    services:
    - name: gitea-ssh
      port: 2222
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
- ingress.yaml
EOF
```

Apply the maniest to the cluster:

```bash
kustomize build ${FLUX_INFRA_DIR}/${CLUSTER}/git-system | kubectl apply -f - 
```

## Admin account creation

You need to manually create the initial admin user for gitea (Note that you
*cannot* use the username `admin`, which is reserved), this example uses the
name `root` and the email address `root@example.com`, but you can use whatever
you want:

```env
GITEA_USER=root
GITEA_EMAIL=root@example.com
```

```bash
kubectl -n git-system exec statefulset/gitea -it -- gitea admin user create \
    --username ${GITEA_USER} --random-password --admin --email ${GITEA_EMAIL}
```

The password is randomly generated and printed, but its at the top of the
output, so you may need to scroll up to see it. Once you sign in using this
account, you can create additional accounts through the web interface.

You can now login to the git service with your web browser, open
https://git.k3s.example.com and login in with the user just created.

## Create flux-infra repository on gitea

Up to now your `flux-infra` repository has only existed on your workstation. Now
you will push it to gitea as a git remote.

 * Login to gitea, and add your workstation SSH key. Go to Settings / SSH Keys
   and click `Add Key` and paste your key (`${HOME}/.ssh/id_rsa.pub`)
 * Create a new repository, using the `+` icon in the upper right of the page.
   Find the SSH clone URL of the blank repository.

```env
GIT_REMOTE=ssh://git@git.${CLUSTER}:2222/${GITEA_USER}/flux-infra.git
```

Commit all the changes so far:

```bash
git -C ${FLUX_INFRA_DIR} init
git -C ${FLUX_INFRA_DIR} add .
git -C ${FLUX_INFRA_DIR} commit -m "initial"
```

Push your local repository:

```bash
git -C ${FLUX_INFRA_DIR} remote add origin ${GIT_REMOTE}
git -C ${FLUX_INFRA_DIR} push -u origin master
```

## Mirror repositories to GitHub or elsewhere

You can mirror your gitea repositories to another git host, like GitHub. This
has to be setup seperately for each repository you wish to mirror.

Create a new SSH key to use as a deploy key:

```bash
SSH_KEY_TMP=$(mktemp -u)
ssh-keygen -C gitea-mirror-$RANDOM -P '' -f ${SSH_KEY_TMP}
echo "------ SSH Public Key printed on next line : ------"
cat ${SSH_KEY_TMP}.pub
```

Do not enter a passphrase, it must be an unencrypted SSH key. The public key
will be printed, which you will need to copy. Create a new repository on GitHub.
Go to the settings, then `Deploy keys` and create a new deploy key, and paste
the public key.

Now copy the private key:

```bash
cat ${SSH_KEY_TMP}
```

Go to the gitea repository settings, go to `Git Hooks`, edit the hook called
`post-receive` and enter this script:

```
#!/bin/bash
MIRROR_REPO="git@github.com:GITHUB_USERNAME/GITHUB_REPO_NAME.git"
KNOWNHOSTS=$(mktemp)

## Public known ssh key for github:
cat <<'EOF' > ${KNOWNHOSTS}
github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
EOF

## Private ssh deploy key for remote mirror:
KEYFILE=$(mktemp)
cat <<'EOF' > ${KEYFILE}
-----BEGIN OPENSSH PRIVATE KEY-----
  YOUR DEPLOY KEY GOES HERE
-----END OPENSSH PRIVATE KEY-----
EOF

## Push changes to mirror using deploy key and known hosts file:
GIT_SSH_COMMAND="/usr/bin/ssh -i ${KEYFILE} -o UserKnownHostsFile=${KNOWNHOSTS}" git push --mirror ${MIRROR_REPO}
rm ${KNOWNHOSTS}
rm ${KEYFILE}
```

You need to change `MIRROR_REPO` to be the git SSH URL for the remote github
repository. Also change the SSH key (starting with `----BEGIN OPENSSH PRIVATE
KEY` and ending with `----END OPENSSH PRIVATE KEY`) to the contents of the
private key just echoed.

Save the Git Hook. Now when you push to this repository, it will automatically
be pushed to the mirror as well.

Delete the temporary ssh key from your workstation:

```bash
rm ${SSH_KEY_TMP}
```

## Setup command line gitea client

`tea` is a command line gitea interface, with it, you can create new git
repositories, and other tasks, directly from your BASH shell.

Login to your gitea account, go to user `Settings`->`Applications`, then click
`Generate Token`. Create a variable to contain the token:

```env
## Gitea App Token
GITEA_TOKEN=xxx
```

Now login with the client:

```bash
tea login add --url https://git.${CLUSTER} --token ${GITEA_TOKEN}
unset GITEA_TOKEN
```

NOTE: your gitea token is stored, unencrypted, at
`${HOME}/.config/tea/config.yml`

Test that it is working; list all of your repos:

```bash
tea repo list
```

