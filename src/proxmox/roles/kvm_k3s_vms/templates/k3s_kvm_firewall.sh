source /etc/firewall_helpers.sh

## SSH port forwards for k3s: 2201, 2202, 2203
port_forward 2201 {{ proxmox_trunk_ip_prefix }}.2.101 22
port_forward 2202 {{ proxmox_trunk_ip_prefix }}.2.102 22
port_forward 2203 {{ proxmox_trunk_ip_prefix }}.2.103 22
## Kubernetes API port for the master k3s node only:
port_forward 6443 {{ proxmox_trunk_ip_prefix}}.2.101 6443
