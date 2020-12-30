---
title: "K3s part 11: Drone"
date: "2020-12-27T00:11:00-06:00"
tags: ['k3s']
---

[Drone](https://www.drone.io/) is a self-hosted Continuous Integration platform,
an equivalent to GitHub Actions, Jenkins, Travis CI, or similar. Drone will
automatically run jobs in response to commits to git repositories in Gitea
(previously setup in [Part 4](/blog/k3s/k3s-04-git)).

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
NAMESPACE=drone
PVC_SIZE=5Gi
GITEA_SERVER=https://git.${CLUSTER}
REGISTRY=registry.${CLUSTER}
```

## Create Gitea OAuth2 app and keys

Drone needs to authenticate with Gitea, using OAuth2. Create the OAuth2 app in
the Gitea settings:

 * Go to your personal settings page in Gitea.
 * Click `Applications`
 * Find `Manage OAuth2 Application` and `Create a new OAuth2 Application`
 * Enter the `Application Name` (`drone`)
 * Enter the `Redirect URI` (`https://drone.k3s.example.com/login`)
 * Click `Create Application`
 * Find and copy the generated `Client ID` and `Client Secret`, you will need to
   enter these values as variables:
   
```env
GITEA_CLIENT_ID=xxxx
GITEA_CLIENT_SECRET=xxxx
```

## Create drone namespace

Create `kustomization.yaml` to list all of the manifests:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- rbac.yaml
- serviceaccounts.yaml
- sealed_secret.yaml
- pvc.yaml
- statefulset.yaml
- ingress.yaml
- secrets-plugin.yaml
- runner.yaml
EOF
```

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
```

## Create Sealed Secret

Generate keys:

```bash
RPC_SECRET=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
KUBERNETES_SECRET_KEY=$(head -c 16 /dev/urandom | sha256sum | head -c 32)
```


```bash
kubectl create secret generic drone \
   --namespace ${NAMESPACE} --dry-run=client -o json \
   --from-literal=GITEA_CLIENT_ID=${GITEA_CLIENT_ID} \
   --from-literal=GITEA_CLIENT_SECRET=${GITEA_CLIENT_SECRET} \
   --from-literal=GITEA_SERVER=${GITEA_SERVER} \
   --from-literal=SERVER_HOST=drone.${CLUSTER} \
   --from-literal=RPC_SECRET=${RPC_SECRET} \
   --from-literal=REGISTRY_DOMAIN=${REGISTRY_DOMAIN} \
   --from-literal=KUBERNETES_SECRET_KEY=${KUBERNETES_SECRET_KEY} \
   | kubeseal -o yaml > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/sealed_secret.yaml
```

## Create Roles and RoleBindings

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/rbac.yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAMESPACE}
  name: drone-runner
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - create
  - delete
- apiGroups:
  - ""
  resources:
  - pods
  - pods/log
  verbs:
  - get
  - create
  - delete
  - list
  - watch
  - update

---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: drone-runner
  namespace: ${NAMESPACE}
subjects:
- kind: ServiceAccount
  name: drone-runner
  namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: drone-runner
  apiGroup: rbac.authorization.k8s.io

---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAMESPACE}
  name: drone-secrets
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - watch

---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: drone-secrets
  namespace: ${NAMESPACE}
subjects:
- kind: ServiceAccount
  name: drone-secrets
  namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: drone-secrets
  apiGroup: rbac.authorization.k8s.io
EOF
```

## Create ServiceAccounts

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/serviceaccounts.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: ${NAMESPACE}
  name: drone-runner
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: ${NAMESPACE}
  name: drone-secrets
EOF
```

## Create PersistentVolumeClaim

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drone-data
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: local-path
EOF
```

## Create StatefulSet

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/statefulset.yaml
apiVersion: v1
kind: Service
metadata:
  name: drone
  namespace: ${NAMESPACE}
spec:
  ports:
  - name: web
    port: 80
    protocol: TCP
  selector:
    app: drone
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app: drone
  name: drone
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  serviceName: drone
  selector:
    matchLabels:
      app: drone
  template:
    metadata:
      labels:
        app: drone
    spec:
      containers:
      - image: drone/drone:1
        name: drone
        volumeMounts:
          - name: data
            mountPath: /data
        ## debug:
        ## command: ["/bin/sh", "-c", "sleep 99999999999"]
        ports:
        - containerPort: 80
          name: web
        env:
          - name: DRONE_GITEA_CLIENT_ID
            valueFrom:
              secretKeyRef:
                name: drone
                key: GITEA_CLIENT_ID
          - name: DRONE_GITEA_CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                name: drone
                key: GITEA_CLIENT_SECRET
          - name: DRONE_GITEA_SERVER
            valueFrom:
              secretKeyRef:
                name: drone
                key: GITEA_SERVER
          - name: DRONE_GIT_ALWAYS_AUTH
            value: "true"
          - name: DRONE_RPC_SECRET
            valueFrom:
              secretKeyRef:
                name: drone
                key: RPC_SECRET
          - name: DRONE_SERVER_HOST
            valueFrom:
              secretKeyRef:
                name: drone
                key: SERVER_HOST
          - name: DRONE_SERVER_PROTO
            value: https
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: drone-data
EOF
```

## Create IngressRoute

```bash
cat <<EOF | sed 's/@@@/`/g' > \
   ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: drone
  namespace: ${NAMESPACE}
spec:
  entryPoints:
  - websecure
  routes:
  - kind: Rule
    match: Host(@@@drone.${CLUSTER}@@@)
    services:
    - name: drone
      port: 80
  tls:
    certResolver: default
EOF
```

## Create Runner

This is the worker that runs jobs on the cluster.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/runner.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: drone-runner
  name: drone-runner
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: drone-runner
  template:
    metadata:
      labels:
        app: drone-runner
    spec:
      serviceAccountName: drone-runner
      containers:
      - image: drone/drone-runner-kube:latest
        name: drone-runner
        env:
          - name: DRONE_NAMESPACE_DEFAULT
            value: ${NAMESPACE}
          - name: DRONE_RPC_SECRET
            valueFrom:
              secretKeyRef:
                name: drone
                key: RPC_SECRET
          - name: DRONE_RPC_HOST
            valueFrom:
              secretKeyRef:
                name: drone
                key: SERVER_HOST
          - name: DRONE_RPC_PROTO
            value: https
          - name: DRONE_SECRET_PLUGIN_ENDPOINT
            value: http://drone-secrets-plugin.${NAMESPACE}.svc.cluster.local:3000
          - name: DRONE_SECRET_PLUGIN_TOKEN
            valueFrom:
              secretKeyRef:
                name: drone
                key: KUBERNETES_SECRET_KEY
EOF
```

## Create Secrets Plugin

This will allow Drone runners to receive secrets from Kubernetes Secrets.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/secrets-plugin.yaml
apiVersion: v1
kind: Service
metadata:
  name: drone-secrets-plugin
  namespace: ${NAMESPACE}
spec:
  ports:
  - name: web
    port: 3000
    protocol: TCP
  selector:
    app: drone-secrets-plugin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: drone-secrets-plugin
  name: drone-secrets-plugin
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: drone-secrets-plugin
  template:
    metadata:
      labels:
        app: drone-secrets-plugin
    spec:
      serviceAccountName: drone-secrets
      containers:
      - name: secrets
        image: drone/kubernetes-secrets:latest
        ports:
        - containerPort: 3000
        env:
        - name: SERVER_ADDRESS
          value: ":3000"
        - name: KUBERNETES_NAMESPACE
          value: ${NAMESPACE}
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: drone
              key: KUBERNETES_SECRET_KEY
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

## Connect drone to gitea

Open your browser to https://drone.k3s.example.com and you should see a
confirmation dialog to autorize drone to access gitea. Proceed and click
`Authorize Application`, and you should be redirected to the drone admin UI,
which lists gitea repositories.

## Create a simple Job Pipeline

Create a new git repository, to hold a new example project:

```env
TEST_REPO=test-drone
TEST_DIR=${HOME}/git/${TEST_REPO}
```

```bash
tea repo create --private --name ${TEST_REPO}
CLONE_URL=$(tea repo | grep -o "ssh://.*[ $]" | grep "/${TEST_REPO}.git[ $]")
```

 * Go to your drone instance (https://drone.k3s.example.com), and click `Sync`
   to refresh the list of repositories. Find the new repository called
   `test-drone` and click `Activate`, then `Activate Repository`.
 * Clone the repo to your workstation, via SSH:
  
```bash
git clone ${CLONE_URL} ${TEST_DIR}
```

Create the drone config file:  `.drone.yml`:

```bash
cat <<EOF > ${TEST_DIR}/.drone.yml
kind: pipeline
type: kubernetes
name: default

steps:
- name: hello-world
  image: alpine:3
  commands:
  - echo hello world
  - echo bye
EOF
```

Note the `type: kubernetes`, this means that the pipeline will run directly on
the cluster, as a pod.

Add, Commit, and Push the change to the gitea repository:

```bash
git -C ${TEST_DIR} add .drone.yml
git -C ${TEST_DIR} commit -m "hello-world"
git -C ${TEST_DIR} push
```

Go to your drone instance, and find the `test-drone` repository again. You
should see a new job in the Activity Feed called `hello-world` (Or whatever your
git commit message was.) At the bottom you should see the step called
`hello-world` and in the output you should see the message `hello world` and
`bye`. The job is working!

```
+ echo hello world
hello world
+ echo bye
bye
```

You can find more complex job pipeline examples in the [drone
docs](https://docs.drone.io/pipeline/kubernetes/examples/)
