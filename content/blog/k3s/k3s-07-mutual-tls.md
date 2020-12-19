---
title: "K3s part 7: Mutual TLS authentication with Traefik"
date: 2020-12-11T00:07:00-06:00
tags: ['k3s']
---

In [part 3](/blog/k3s/k3s-03-traefik), the Traefik IngressRoute for the `whoami`
service was configured with TLS certificates from Let's Encrypt. This type of
certificate only authenticates the server, not the client, leaving client
authentication as a requirement on the application layer. (For example,
requiring to submit a username/password via HTTP, before access is granted.)
This is enough, and normal, for secure public facing web services, where your
clients might be connecting from anywhere, especially using web-browsers.

However, TLS certificates (X.509) can be used on the client too. This is rare
for web-browsers, but is very common place for business and subscription API
services. This forms bi-directional authentication: client authenticates server
*and* server authenticates client: Mutual TLS. This authentication happens at
the session layer, meaning that you will probably still want to use usernames
and passwords at the application layer, as an extra barrier to entry before
authorization, but you gain extra confidence to know that the only clients that
can approach your application, are already holding a signed certificate allowing
them to do so.

If you're familiar with SSH keys, Mutual TLS is kind of like configuring sshd
with `PubkeyAuthentication yes` and `PasswordAuthentication no`, thus requiring
a key from each client, and denying those without keys. However, with TLS you
don't need to list each and every key that you wish to allow (there is no
equivalent to the SSH `authorized_keys` file), but rather TLS verifies that the
key is signed by your (self-hosted) Certificate Authority. In the case of
Traefik, you can enforce this on a per-route (sub-domain matching) basis, with
separate Certificate Authorities for each route.

## Certificate Authority

In order to generate and sign client certificates, a new Certificate Authority
must be created. Let's Encrypt cannot be used for generating client
certificates, but will continue to be used for the server certificates.

To generate the client certificates, you will use a program called [Step
CLI](https://github.com/smallstep/cli) using the provided docker image. Its
advisable to keep your root CA offline, so you will create this only on your
workstation, via podman, *not on the cluster*.

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
## Name of root CA file:
ROOT_CA=my_org_root_ca
## Name on root CA certificate:
ROOT_CA_NAME="Example Organization Root CA"
## Podman volume to store keys and certs:
CA_VOLUME=RootCertificateAuthority
```

Create a podman volume to store the root CA key and all generated certificates:
```bash
podman volume create ${CA_VOLUME}
```

Create a temporary alias to run things in the container:
```bash
alias step_run="podman run --rm -it -v \
  ${CA_VOLUME}:/home/step smallstep/step-ca"
```

## Generate Root CA

You will create one Root CA that will be used to sign all intermediate CAs:

```bash
step_run step certificate create \
   --profile root-ca "${ROOT_CA_NAME}" ${ROOT_CA}.crt ${ROOT_CA}.key
```

Choose a strong passphrase, when asked to encrypt the root CA.

## Generate Intermediate CA for a single service

You will create Intermediate CAs for smaller organizational grouping. You could
create one per cluster, one per namespace, or one per service. This is the
example for creating an Intermediate CA just for the `whoami` service running in
a specific namespace (In [part 3](/blog/k3s/k3s-03-traefik) you created a
different `whoami` service in the default namespace, this will be another
`whoami` service in a new namespace for testing):

```env
SERVICE=whoami-mtls
NAMESPACE=whoami-mtls
INTERMEDIATE_CA=${SERVICE}.${CLUSTER}
```

```bash
step_run step certificate create "${INTERMEDIATE_CA} Intermediate" \
    ${INTERMEDIATE_CA}-intermediate_ca.crt ${INTERMEDIATE_CA}-intermediate_ca.key \
    --profile intermediate-ca --ca ./${ROOT_CA}.crt --ca-key ./${ROOT_CA}.key
```

You must again enter the passphrase for the ROOT CA, and choose a new passphrase
for the Intermediate CA.

## Export the public CA certificates

```bash
CA_CERT=$(mktemp)
step_run cat ${INTERMEDIATE_CA}-intermediate_ca.crt > ${CA_CERT}
step_run cat ${ROOT_CA}.crt >> ${CA_CERT}
echo "--------------------------"
echo Certificate chain exported: ${CA_CERT}
```

## Create the namespace

Create a new namespace for testing Mutual TLS:

```bash
mkdir -p ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- ${SERVICE}.tls.sealed_secret.yaml
- ${SERVICE}.tls.yaml
- ${SERVICE}.yaml
- ${SERVICE}.ingressroute.yaml
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


## Create the Sealed Secret containing CA certificates

```bash
kubectl create secret generic ${SERVICE}-certificate-authority \
   --namespace ${NAMESPACE} --dry-run=client -o json \
   --from-file=tls.ca=${CA_CERT} | kubeseal -o yaml > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/${SERVICE}.tls.sealed_secret.yaml
```

## Create the TLSOption

The
[TLSOption](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-tlsoption)
that will require valid signed certificates from the whoami Intermediate CA:

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/${SERVICE}.tls.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: TLSOption
metadata:
  name: ${SERVICE}
  namespace: ${NAMESPACE}

spec:
  clientAuth:
    # the CA certificate is extracted from key 'tls.ca' of the given secrets.
    secretNames:
      - ${SERVICE}-certificate-authority
    clientAuthType: RequireAndVerifyClientCert
EOF
```

## Create the whoami service

```bash
cat <<EOF > ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/${SERVICE}.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE}
  namespace: ${NAMESPACE}

spec:
  ports:
  - name: web
    port: 80
    protocol: TCP
  selector:
    app: ${SERVICE}
---
apiVersion: traefik.containo.us/v1alpha1
kind: TraefikService
metadata:
  name: ${SERVICE}
  namespace: ${NAMESPACE}

spec:
  weighted:
    services:
      - name: ${SERVICE}
        weight: 1
        port: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: ${SERVICE}
  name: ${SERVICE}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${SERVICE}
  template:
    metadata:
      labels:
        app: ${SERVICE}
    spec:
      containers:
      - image: containous/whoami
        name: whoami
        ports:
        - containerPort: 80
          name: web
EOF
```

## Create the IngressRoute

The
[IngressRoute](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-ingressroute)
binds this route with a specific TLSOption, which requires our signed
certificate:

```bash
cat <<EOF | sed 's/@@@/`/g' > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/${NAMESPACE}/${SERVICE}.ingressroute.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ${SERVICE}
  namespace: ${NAMESPACE}
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  entryPoints:
  - websecure
  routes:
  - kind: Rule
    match: Host(@@@${SERVICE}.${CLUSTER}@@@)
    services:
    - name: ${SERVICE}
      port: 80
  tls:
    certResolver: default
    ## Bind this route to a specific TLSOption object:
    options:
      name: ${SERVICE}
      namespace: ${NAMESPACE}
EOF
```

## Commit the changes

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} ${SERVICE} TLSOptions"
```

```bash
git -C ${FLUX_INFRA_DIR} push
```

## Test the result

Wait a minute for flux to apply the changes to the cluster, then check in your
web-browser, load https://whoami.k3s.example.com, you should expect to see an
error telling you that the client certificate was not provided.
(`ERR_BAD_SSL_CLIENT_AUTH_CERT`)

Now test with curl:

```bash
curl https://${SERVICE}.${CLUSTER}
```

You should again expect an error, `bad certificate, errno 0`.

No one can access the whoami service without a valid client certificate!

## Generate client certificates

```env
## Certificate expiration time (1 year):
EXPIRATION=8760h
```

```bash
step_run step certificate create ${SERVICE}-client \
    ${SERVICE}-client.crt ${SERVICE}-client.key \
    --profile leaf --not-after=${EXPIRATION} \
    --ca ${INTERMEDIATE_CA}-intermediate_ca.crt \
    --ca-key ${INTERMEDIATE_CA}-intermediate_ca.key \
    --insecure --no-password --bundle
```

You will need to enter the password for the Intermediate CA. 

Now export the client certificate and key:

```bash
CLIENT_CERT=$(mktemp)
CLIENT_KEY=$(mktemp)
step_run cat ${SERVICE}-client.crt >> ${CLIENT_CERT}
step_run cat ${SERVICE}-client.key >> ${CLIENT_KEY}
echo "--------------------------"
echo Client cert exported: ${CLIENT_CERT}
echo Client key exported: ${CLIENT_KEY}
```

## Test curl with certificates

Now you should have access to the whoami service using the certificate and key:

```bash
curl --cert ${CLIENT_CERT} --key ${CLIENT_KEY} https://${SERVICE}.${CLUSTER}
```

This uses your client certificate and client key, to authenticate with the
server. curl verifies the signature of the advertised server certificate (from
Let's Encrypt) with the local TLS trust store (`ca-certificates` package). If
instead, you wanted to verify the exact CA, you can specify the file explicitly:

```bash
# Download the known Let's Encrypt Intermediate CA certificate:
# NOTE: This URL might change in the future, look it up:
# https://letsencrypt.org/certificates/
LETSENCRYPT_CA=$(mktemp)
curl -L https://letsencrypt.org/certs/lets-encrypt-r3.pem > ${LETSENCRYPT_CA}
```

```bash
curl --cert ${CLIENT_CERT} --key ${CLIENT_KEY} \
   --cacert ${LETSENCRYPT_CA} https://${SERVICE}.${CLUSTER}
```
## Using client certificates in programs

Here is a [big list of examples from
smallstep](https://smallstep.com/hello-mtls), including Python, Node.js, Go etc.

## Backup podman volume

You can export a tarball of the docker volume, this will include all of the
certificates and keys for your CA and clients. Keep it safe!!

```bash
podman run --rm -v ${CA_VOLUME}:/home/step smallstep/step-ca \
   tar cz /home/step > ${ROOT_CA}.tar.gz
echo "Saved ROOT CA backup: $(pwd)/${ROOT_CA}.tar.gz"
```
