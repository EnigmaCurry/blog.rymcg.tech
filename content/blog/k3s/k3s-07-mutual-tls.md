---
title: "K3s part 7: Mutual TLS authentication with Traefik"
date: 2020-12-11T00:07:00-06:00
tags: ['k3s']
---

In [part 3](/blog/k3s/k3s-03-traefik), Traefik was configured with TLS certificates
from Let's Encrypt. This type of certificate only authenticates the server, not
the client, leaving client authentication as a requirement on the application
layer. (For example, requiring to submit a username/password via HTTP, before
access is granted.) This is enough, and normal, for secure public facing web
services, where your clients might be connecting from anywhere.

However, TLS certificates (X.509) can be used on the client too. This forms
bi-directional authentication: client authenticates server *and* server
authenticates client: Mutual TLS. This authentication happens at the session
layer, meaning that you will probably still want to use usernames/passwords at
the application layer as an extra layer of enforcement before authorization, but
it gives you extra confidence that the only clients that will ever connect to
your application, are already holding a signed certificate allowing them to do
so.

If you're familiar with SSH keys, Mutual TLS is like setting
`PasswordAuthentication no` in `sshd_config`, thus requiring a key from each
client, except its for TLS (https) not SSH, and that in the case of Traefik, you
can enforce this on a per-route (URL or domain matching) basis.

## Certificate Authority

In order to generate client certificates, a new Certificate Authority must be
created. Let's Encrypt cannot be used for generating client certificates.

To generate the certificates, you will use a program called [Step
CLI](https://github.com/smallstep/cli) using the provided docker image. Its
advisable to keep your root CA offline, so you will create this only on your
workstation, via podman, *not on the cluster*:

```env
## Same git repo for infrastructure as in prior posts:
FLUX_INFRA_DIR=${HOME}/git/flux-infra
CLUSTER=k3s.example.com
## Name of root CA file:
ROOT_CA=root_ca
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

## Generate Intermediate CAs

You will create Intermediate CAs for smaller organizational grouping. You could
create one per cluster, one per namespace, or one per service. This is the
example for creating an Intermediate CA just for the `whoami` service:

```env
INTERMEDIATE_CA=whoami.${CLUSTER}
```

```bash
step_podman certificate create "${INTERMEDIATE_CA} Intermediate" \
    ${INTERMEDIATE_CA}-intermediate_ca.crt ${INTERMEDIATE_CA}-intermediate_ca.key \
    --profile intermediate-ca --ca ./${ROOT_CA}.crt --ca-key ./${ROOT_CA}.key
```

You must again enter the passphrase for the ROOT CA, and choose a new passphrase
for the Intermediate CA.

## Export the public certificates

```bash
CA_CERT=$(mktemp)
step_run cat ${INTERMEDIATE_CA}-intermediate_ca.crt > ${CA_CERT}
step_run cat ${ROOT_CA}.crt >> ${CA_CERT}
echo "--------------------------"
echo Certificate chain exported: ${CA_CERT}
```

## Create the Sealed Secret containing CA certificates

```
kubectl create secret generic whoami-certificate-authority \
   --namespace default --dry-run=client -o json \
   --from-file=tls.ca=${CA_CERT} | kubeseal -o yaml > \
  ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/whoami-tls.sealed_secret.yaml
```

Add the sealed secret to the list of resources in `kustomization.yaml`:

```bash
echo "- whoami-tls.sealed_secret.yaml" >> ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/kustomization.yaml
```

## Create the TLSOption

The TLSOption that will require valid signed certificates from the whoami
Intermediate CA:

```bash
cat <<'EOF' > ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/whoami.tls.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: TLSOption
metadata:
  name: whoami
  namespace: default

spec:
  clientAuth:
    # the CA certificate is extracted from key 'tls.ca' of the given secrets.
    secretNames:
      - whoami-certificate-authority
    clientAuthType: RequireAndVerifyClientCert
EOF
```

Add the TLS options to the list of resources in `kustomization.yaml`:

```bash
echo "- whoami.tls.yaml" >> ${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/kustomization.yaml
```


## Modify the whoami ingress

Edit the whoami IngressRoute, at the bottom of `whoami.yaml`

```bash
WHOAMI_YAML=${FLUX_INFRA_DIR}/${CLUSTER}/kube-system/whoami.yaml
${EDITOR:-nano} ${WHOAMI_YAML}
```

At the bottom of the file is the `IngressRoute`, see the section that says
`tls`, you must add the `options` beneath that:

```
  tls:
    certResolver: default
    options:
      name: whoami
      namespace: default
```

Save the file.

This tells the whoami Ingress to use the whoami TLSOption.

## Commit the changes

```bash
git -C ${FLUX_INFRA_DIR} add ${CLUSTER}
git -C ${FLUX_INFRA_DIR} commit -m "${CLUSTER} whoami TLSOptions"
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
curl https://whoami.${CLUSTER}
```

You should again expect an error, `bad certificate, errno 0`.

No one can access the whoami service without a valid client certificate!

## Generate client certificates

```env
## Certificate expiration time (1 year):
EXPIRATION=8760h
```

```bash
step_run step certificate create whoami-client whoami-client.crt whoami-client.key \
    --profile leaf --not-after=${EXPIRATION} \
    --ca ${INTERMEDIATE_CA}-intermediate_ca.crt \
    --ca-key ${INTERMEDIATE_CA}-intermediate_ca.key \
    --insecure --no-password --bundle
```

You will need to enter the password for the Intermediate CA. 

```bash
CLIENT_CERT=$(mktemp)
CLIENT_KEY=$(mktemp)
step_run cat whoami-client.crt >> ${CLIENT_CERT}
step_run cat whoami-client.key >> ${CLIENT_KEY}
echo "--------------------------"
echo Client cert exported: ${CLIENT_CERT}
echo Client key exported: ${CLIENT_KEY}
```

## Test curl with certificates

Now you should have access to the whoami service using the certificate and key:

```bash
curl --cert ${CLIENT_CERT} --key ${CLIENT_KEY} https://whoami.${CLUSTER}
```
