#!/bin/bash -ex

DOMAIN=faas.example.com
TRAEFIK_CA_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory
TRAEFIK_CA_EMAIL=you@example.com
TRAEFIK_VERSION=v2.3.7
FAASD_INSTALLER_SCRIPT=https://raw.githubusercontent.com/openfaas/faasd/master/hack/install.sh

# Enable firewall
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Create traefik config
mkdir -p /etc/traefik/{config.d,acme}
cat <<EOF > /etc/traefik/traefik.toml
[log]
  level = "DEBUG"
[providers.file]
  directory = "/etc/traefik/config.d"
  watch = true
[entrypoints]
  [entrypoints.web]
    address = ":80"
    [entrypoints.web.http.redirections.entrypoint]
      to = "websecure"
      scheme = "https"
  [entrypoints.websecure]
    address = ":443"
[certificatesResolvers.default.acme]
  storage = "/etc/traefik/acme/acme.json"
  tlschallenge = true
  caserver = "${TRAEFIK_CA_SERVER}"
  email = "${TRAEFIK_CA_EMAIL}"
EOF

create_service_proxy() {
    ## Template function to create a traefik configuration for a service.
    ## Creates automatic http to https redirect.
    ## Note: traefik will automatically reload configuration when the file changes.
    SERVICE=$1
    DOMAIN=$2
    PORT=${3:-80}
    cat <<END_PROXY_CONF > /etc/traefik/config.d/${SERVICE}.toml
[http.routers.${SERVICE}]
  entrypoints = "web"
  rule = "Host(\"${DOMAIN}\")"
  middlewares = "${SERVICE}-secure-redirect"
[http.middlewares.${SERVICE}-secure-redirect.redirectscheme]
  scheme = "https"
  permanent = "true"
[http.routers.${SERVICE}-secure]
  entrypoints = "websecure"
  rule = "Host(\"${DOMAIN}\")"
  service = "${SERVICE}"
  [http.routers.${SERVICE}-secure.tls]
    certresolver = "default"
[[http.services.${SERVICE}.loadBalancer.servers]]
  url = "http://localhost:${PORT}/"
END_PROXY_CONF
}

create_service_proxy faasd ${DOMAIN} 8080

# Download traefik
curl -L https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz | tar xvz traefik
install traefik /usr/local/bin
rm traefik

# Create traefik service
cat <<EOF > /etc/systemd/system/traefik.service
[Unit]
After=network-online.target

[Service]
ExecStart=/usr/local/bin/traefik
SyslogIdentifier=traefik
Restart=always

[Install]
WantedBy=network-online.target
EOF

# Start services
systemctl daemon-reload
systemctl enable traefik
systemctl restart traefik

# Install faasd
curl -L ${FAASD_INSTALLER_SCRIPT} | bash -ex
