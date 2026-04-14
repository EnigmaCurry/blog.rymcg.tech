---
title: "Proxmox part 9: Virtual Private Cloud (VPC)"
date: 2026-04-14T00:01:00-06:00
tags: ['proxmox']
draft: true
---

In [part 2](/blog/proxmox/02-networking), we set up NAT bridges where
the Proxmox host itself performs IP masquerading for VMs on private
networks. This is simple and effective, but it means that every VM on
a NAT bridge has a direct path to the internet through the host
kernel. There is no way to inspect, filter, or control that egress
traffic at the VM level.

In this post, we will create a Virtual Private Cloud (VPC): an
isolated network where VMs have **no direct internet access**. The
only path to the outside world is through a dedicated **router VM**
that you fully control. This is similar to how AWS VPCs work: you
create an isolated network, attach a NAT gateway (our router VM), and
only traffic that passes through the gateway can reach the internet.

This is useful for:

 * **Security sandboxing** — run untrusted workloads on a network
   where you control all egress
 * **Testing** — simulate a production network topology with a
   router, firewall, and isolated clients
 * **Multi-tenant isolation** — give each tenant their own VPC with
   a dedicated router

Unlike [part 6](/blog/proxmox/06-router) (which builds a full home
LAN router with physical NIC passthrough), this setup is purely
virtual. No special hardware is required — just a standard Proxmox
installation.

## Architecture

```
                    Internet
                       |
                   [vmbr0]
                    |    |
          Proxmox Host   Router VM
       (management only)  net0: vmbr0 (internet)
        10.99.0.2/24      net1: vmbr99 (VPC gateway)
                    |    |
                   [vmbr99] — VPC Bridge (no host NAT)
                       |
                   Client VM
                    net0: vmbr99 (VPC only)
```

The Proxmox host has a management IP on the VPC bridge (`10.99.0.2`)
so you can SSH to VMs for administration, but the host does **not**
perform any masquerading or IP forwarding for the VPC network. The
only way a client VM can reach the internet is through the router VM.

## Prerequisites

 * Proxmox installed ([part 1](/blog/proxmox/01-install))
 * SSH access to the Proxmox host as `root`

## Download the script

Connect to the Proxmox host via SSH and download the `proxmox_vpc.sh`
script:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_vpc.sh
chmod +x proxmox_vpc.sh
```

Running the script without arguments shows the available commands and
current configuration:

```bash
./proxmox_vpc.sh
```

## Configuration

All settings are controlled by environment variables with sensible
defaults. You can see the full list and their current values by
running `./proxmox_vpc.sh` with no arguments. To override settings,
export them before running commands:

```bash
export VPC_BRIDGE=vmbr50
export VPC_HOST_CIDR=172.16.0.2/24
export STORAGE=local-lvm
```

## Create the VPC

Create the private bridge:

```bash
./proxmox_vpc.sh create_vpc
```

This creates a Linux bridge (`vmbr99` by default) with:

 * `bridge_ports none` — not connected to any physical interface
 * A management IP for the Proxmox host (`10.99.0.2/24`)
 * **No masquerade rules** — the host will not NAT traffic for this bridge
 * **No ip_forward** — the host will not route traffic between this
   bridge and `vmbr0`

This is the key difference from
[part 2](/blog/proxmox/02-networking)'s NAT bridges. The VPC bridge
is just a Layer 2 switch. It connects VMs to each other, but provides
no path to the internet on its own.

You may need to activate the new bridge:

```bash
ifup ${VPC_BRIDGE:-vmbr99}
```

## Create the router VM

The router VM has one foot in each network: `vmbr0` for internet
access and the VPC bridge for the private side.

```bash
./proxmox_vpc.sh create_router
```

This creates a VM with:

 * **net0** on `vmbr0` (internet-facing)
 * **net1** on `vmbr99` (VPC private side)
 * A blank disk (no OS installed)

### Attach an OS ISO

In the Proxmox GUI:

 * Select VM **200** (router)
 * Go to **Hardware** → **CD/DVD Drive**
 * Select an ISO image (any Linux distribution will work)
 * Go to **Options** → **Boot Order** and ensure the CD/DVD drive is
   first for the initial install

Start the VM and install your chosen operating system. During
installation, configure the network interfaces:

 * **net0** (the internet-facing NIC): DHCP or a static IP on your
   LAN, depending on your `vmbr0` setup
 * **net1** (the VPC NIC): static IP `10.99.0.1/24` (this will be the
   gateway for client VMs)

## Configure NAT inside the router VM

After installing the OS on the router VM, you need to enable IP
forwarding and masquerading so that client VMs can reach the internet
through it.

### Enable IP forwarding

```bash
# Run this inside the router VM:
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl --load /etc/sysctl.d/99-ip-forward.conf
```

### Configure nftables

Install nftables if it is not already present, and create the firewall
rules. Replace `eth0` and `eth1` with the actual interface names on
your system (check with `ip link`):

```bash
# Run this inside the router VM:
cat <<'EOF' > /etc/nftables.conf
#!/usr/bin/nft -f

define PUBLIC_INTERFACE = { eth0 }
define VPC_INTERFACE = { eth1 }

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;

    ct state invalid drop
    iif lo accept
    ct state { established, related } accept

    ## Allow ICMP/ICMPv6:
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    ## Allow SSH on all interfaces:
    tcp dport 22 accept

    ## Allow DNS and DHCP from VPC clients:
    iifname $VPC_INTERFACE tcp dport 53 accept
    iifname $VPC_INTERFACE udp dport { 53, 67 } accept

    ## Reject everything else:
    reject with icmpx type admin-prohibited
  }

  chain forward {
    type filter hook forward priority filter; policy drop;

    ct state invalid drop
    ct state { established, related } accept

    ## Allow VPC clients to reach the internet:
    iifname $VPC_INTERFACE oifname $PUBLIC_INTERFACE accept
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}

table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    iifname $VPC_INTERFACE oifname $PUBLIC_INTERFACE masquerade
  }
}
EOF
```

Enable and start nftables:

```bash
# Run this inside the router VM:
systemctl enable --now nftables
systemctl restart nftables
```

Verify the rules:

```bash
# Run this inside the router VM:
nft list ruleset
```

For a more comprehensive nftables configuration with traffic counters
and per-interface controls, see
[part 6](/blog/proxmox/06-router/#create-nftables-rules).

### Optional: DHCP server for VPC clients

If you want client VMs to automatically receive IP addresses instead
of configuring static IPs, you can run dnsmasq on the router's VPC
interface.

On Debian/Ubuntu:

```bash
# Run this inside the router VM:
apt-get update && apt-get install -y dnsmasq
```

On Arch Linux:

```bash
# Run this inside the router VM:
pacman -S --noconfirm dnsmasq
```

Create the configuration:

```bash
# Run this inside the router VM:
# (Replace eth1 with your VPC interface name)
cat <<'EOF' > /etc/dnsmasq.d/vpc.conf
interface=eth1
except-interface=lo
bind-interfaces
listen-address=10.99.0.1
domain=vpc
server=1.1.1.1
server=8.8.8.8
dhcp-range=10.99.0.10,10.99.0.250,255.255.255.0,1h
dhcp-option=3,10.99.0.1
dhcp-option=6,10.99.0.1
EOF
```

Enable and start dnsmasq:

```bash
# Run this inside the router VM:
systemctl enable --now dnsmasq
systemctl restart dnsmasq
```

## Create a client VM

Back on the Proxmox host, create a client VM that is isolated on the
VPC:

```bash
./proxmox_vpc.sh create_vm
```

This creates a VM with:

 * **net0** on `vmbr99` — the **only** network interface, connected
   exclusively to the VPC bridge
 * A blank disk (no OS installed)

Attach an OS ISO in the Proxmox GUI and install the OS, just as you
did for the router. During network configuration:

 * If the router is running dnsmasq: configure DHCP
 * If not: set a static IP on the `10.99.0.0/24` network with
   `10.99.0.1` as the gateway and DNS server (or use `1.1.1.1`)

### Creating additional client VMs

To create more VMs on the same VPC, override the VM ID and hostname:

```bash
CLIENT_VM_ID=202 CLIENT_HOSTNAME=client2 ./proxmox_vpc.sh create_vm
CLIENT_VM_ID=203 CLIENT_HOSTNAME=client3 ./proxmox_vpc.sh create_vm
```

## Testing

Once both VMs are running with their operating systems installed and
configured, verify the setup from inside the client VM:

```bash
# Run this inside the client VM:

## Test connectivity to the router:
ping -c 3 10.99.0.1

## Test internet access through the router:
ping -c 3 1.1.1.1

## Test DNS (if dnsmasq is running on the router):
ping -c 3 google.com
```

### Verify isolation

The client VM should **not** be able to reach the Proxmox host's
management network directly. The host's `vmbr0` address is on a
different network, and since there is no masquerade or ip_forward on
the host for the VPC bridge, the client's only path out is through
the router VM.

You can verify this by checking the routing table on the client:

```bash
# Run this inside the client VM:
ip route
```

The default route should point to `10.99.0.1` (the router VM), not
to the Proxmox host.

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_vpc.sh)

{{< code file="/src/proxmox/proxmox_vpc.sh" language="shell" >}}

## Cleanup

To tear down the entire VPC (both VMs and the bridge):

```bash
./proxmox_vpc.sh destroy
```

This will stop and destroy both VMs, then remove the VPC bridge. You
will be prompted for confirmation before any resources are deleted.
