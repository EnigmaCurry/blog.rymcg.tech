---
title: "K3s part 10: OpenFaaS"
date: "2020-12-25T00:10:00-06:00"
tags: ['k3s']
---

[OpenFaaS](https://www.openfaas.com/) is a platform for creating serverless
functions and microservices on kubernetes. 

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
```

## Add the flux HelmRepository

OpenFaaS is distributed as a helm chart. The easiest way to consume this, is to
add the helm repository directly to flux, and let flux handle it. HelmRepository
objects must be created in the `flux-system` namespace, as shown:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/helm-repositories.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: openfaas
  namespace: flux-system
spec:
  interval: 1m
  url: https://openfaas.github.io/faas-netes/
EOF
```

Update the `flux-system/kustomization.yaml` file, to include the helm
repository:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/flux-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
- helm-repositories.yaml
EOF
```

## Create namespaces for OpenFaaS

Create `kustomization.yaml` to list all of the manifests:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- configmap.yaml
- helm.release.yaml
EOF
```

Create namespaces: `openfaas` is for the system, and `openfaas-fn` is for
running functions:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openfaas
  labels:
    role: openfaas-system
    access: openfaas-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: openfaas-fn
  labels:
    role: openfaas-fn
EOF
```

## Create OpenFaaS helm release

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas/helm.release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: openfaas
  namespace: openfaas
spec:
  interval: 5m
  chart:
    spec:
      chart: openfaas
      sourceRef:
        kind: HelmRepository
        name: openfaas
        namespace: flux-system
      interval: 1m
  valuesFrom:
  - kind: ConfigMap
    name: openfaas
    valuesKey: values.yaml
EOF
```

## Create Helm values

You can refer to the [upstream chart
values.yaml](https://github.com/openfaas/faas-netes/blob/master/chart/openfaas/values.yaml)
for settings.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openfaas
  namespace: openfaas
data:
  values.yaml: |
    functionNamespace: openfaas-fn
    generateBasicAuth: true
    serviceType: ClusterIP
    operator:
      create: true
    ingress:
      enabled: true
      hosts:
      - host: gateway.faas.${CLUSTER}
        serviceName: gateway
        servicePort: 8080
        path: /
      annotations:
        kubernetes.io/ingress.class: traefik
        traefik.ingress.kubernetes.io/router.tls.certresolver: default
EOF
```

## Commit and push manfests

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} OpenFaaS"
```

```bash
git -C ${FLUX_INFRA_DIR} push
```

## Login to OpenFaaS

Go to https://gateway.faas.k3s.example.com in your browser

The Username is `admin` - the Password can be obtained by running:

```bash
PASSWORD=$(kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 -d)
echo "OpenFaaS username: admin"
echo "OpenFaaS password: ${PASSWORD}"
```

Login using `faas-cli`:

```bash
export OPENFAAS_URL=https://gateway.faas.${CLUSTER}
echo -n ${PASSWORD} | faas-cli login -g ${OPENFAAS_URL} -u admin --password-stdin
```

## Create test function

Create a new git repository someplace to create functions

```env
FUNCTIONS_ROOT=${HOME}/git/functions
REGISTRY=registry.${CLUSTER}
FUNCTION=hello-python
LANGUAGE=python
export OPENFAAS_URL=https://gateway.faas.${CLUSTER}
```


```bash
mkdir -p ${FUNCTIONS_ROOT}
git init ${FUNCTIONS_ROOT}
(cd ${FUNCTIONS_ROOT}; faas-cli new --prefix ${REGISTRY}/functions \
  --lang ${LANGUAGE} ${FUNCTION})
```

Create the Dockerfile for the container:

```bash
(cd ${FUNCTIONS_ROOT}; faas-cli build -f ${FUNCTION}.yml --shrinkwrap)
echo "Dockerfile created in ${FUNCTIONS_ROOT}/build/${FUNCTION}"
```

## Build the function image

In order to build the image for the test function you will use `podman`.

```bash
podman build -f ${FUNCTIONS_ROOT}/build/${FUNCTION} \
  -t ${REGISTRY}/functions/${FUNCTION}
```

Login to the registry with podman:

```bash
podman login ${REGISTRY}
```

(Recall the username and password created when you setup the registry. Or check
`/etc/rancher/k3s/registries.yaml` on the k3s node.)

Push the image to the registry:

```bash
podman push ${REGISTRY}/functions/${FUNCTION}
```

## Deploy the test function

Create the manifests for the openfaas-fn namespace:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas-fn
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas-fn/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- test-functions.yaml
EOF
```

OpenFaaS functions can be declared in kubernetes with a [Function
CRD](https://github.com/openfaas/faas-netes/blob/master/README-OPERATOR.md)
object.

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/openfaas-fn/test-functions.yaml
apiVersion: openfaas.com/v1
kind: Function
metadata:
  name: ${FUNCTION}
  namespace: openfaas-fn
spec:
  name: ${FUNCTION}
  image: ${REGISTRY}/functions/${FUNCTION}
  labels:
    com.openfaas.scale.min: "2"
    com.openfaas.scale.max: "15"
  environment:
    write_debug: "true"
  limits:
    cpu: "200m"
    memory: "256Mi"
  requests:
    cpu: "10m"
    memory: "128Mi"
EOF
```

## Commit and push manfests

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} OpenFaaS functions"
```

```bash
git -C ${FLUX_INFRA_DIR} push
```


## Test the function

Test the function responds:

```bash
curl -v -d "It works!" \
  https://gateway.faas.${CLUSTER}/function/${FUNCTION}.openfaas-fn
```

It should respond with debug headers and an echo of the text you sent: `It
works!`

```
...
< HTTP/2 200 
< content-type: application/x-www-form-urlencoded
< date: Sat, 26 Dec 2020 20:11:38 GMT
< x-duration-seconds: 0.076057
< content-length: 10
< 
It works!
...
```

See the contents of the handler function:

```bash
HANDLER=${FUNCTIONS_ROOT}/build/${FUNCTION}/index.py
cat ${HANDLER}
echo "## Next steps:"
echo "## Modify ${HANDLER} to change this function"
echo "## Rebuild and push image to registry"
echo "## Redeploy function"
```
