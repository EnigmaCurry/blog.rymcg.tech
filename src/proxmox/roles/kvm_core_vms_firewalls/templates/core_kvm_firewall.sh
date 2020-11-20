source /etc/firewall_helpers.sh

port_forward 2222 {{ proxmox_trunk_ip_prefix }}.1.101 22
port_forward 2223 {{ proxmox_trunk_ip_prefix }}.2.101 22
port_forward 2224 {{ proxmox_trunk_ip_prefix }}.2.102 22

port_open_tcp {{ proxmox_public_interface }} {{ proxmox_master_ip }} 2222
