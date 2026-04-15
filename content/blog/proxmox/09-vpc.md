---
title: "Proxmox part 9: Virtual Private Cloud (VPC)"
date: 2026-04-14T00:01:00-06:00
tags: ['proxmox']
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
## VPC Bridge:
export VPC_BRIDGE=vmbr99
export VPC_HOST_CIDR=10.99.0.2/24

## Router VM:
export ROUTER_VM_ID=200
export ROUTER_HOSTNAME=router
export ROUTER_DISK_SIZE=32G
export ROUTER_MEMORY=2048
export ROUTER_CORES=1
export PUBLIC_BRIDGE=vmbr0

## Client VM:
export CLIENT_VM_ID=201
export CLIENT_HOSTNAME=client
export CLIENT_DISK_SIZE=32G
export CLIENT_MEMORY=2048
export CLIENT_CORES=1

## Storage:
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

### Load an OS ISO

The VM is created with an empty CD/DVD drive. In the Proxmox GUI:

 * Select VM **200** (router)
 * Go to **Hardware** → double-click the **CD/DVD Drive**
 * Select an ISO image (any Linux distribution will work)
 * Go to **Options** → **Boot Order** and ensure the CD/DVD drive is
   first for the initial install

## Install nifty-filter on the router VM

[nifty-filter](https://github.com/EnigmaCurry/nifty-filter) is an
immutable NixOS router distribution that provides everything the
router VM needs: nftables firewall, DHCP server, DNS server, and
network routing. It runs on a read-only root filesystem with
configuration stored on a read-write `/var` partition.

### Build the ISO

On a machine with Nix installed, clone and build the nifty-filter ISO:

```bash
git clone https://github.com/EnigmaCurry/nifty-filter.git
cd nifty-filter
nix build .#iso
```

Upload the resulting ISO to the Proxmox host's ISO storage (or use
the Proxmox GUI to upload it).

### Install nifty-filter

 * Load the nifty-filter ISO into the router VM's CD/DVD drive
 * Start the VM and open the console
 * Log in with the default credentials: `admin` / `nifty`
 * Run the interactive installer:

```bash
nifty-install
```

The installer will prompt you for:

 * **Hostname** — e.g., `router`
 * **Disk** — select the virtual disk to install to
 * **WAN interface** — the upstream interface (net0, connected to
   `vmbr0`)
 * **LAN interface** — the VPC interface (net1, connected to the
   VPC bridge)
 * **Subnet configuration** — use `10.99.0.1/24` for the VPC side
 * **DNS servers** — upstream DNS resolvers

After installation, reboot the VM. nifty-filter will automatically
configure IP forwarding, nftables masquerade, DHCP, and DNS for the
VPC network.

### Configure nifty-filter

After the initial install, you can reconfigure at any time:

```bash
# Run this inside the router VM:
nifty-config
```

Or edit the configuration files directly in `/var/nifty-filter/`:

 * `router.env` — firewall rules and interface configuration
 * `dhcp.env` — DHCP pool settings and DNS configuration

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

Load an OS ISO into the CD/DVD drive in the Proxmox GUI and install
the OS, just as you did for the router. The nifty-filter DHCP server
will automatically assign an IP address and configure the default
gateway, so the client should be able to use DHCP with no additional
configuration.

### Creating additional client VMs

To create more VMs on the same VPC, override the VM ID and hostname:

```bash
CLIENT_VM_ID=202 CLIENT_HOSTNAME=client2 ./proxmox_vpc.sh create_vm
CLIENT_VM_ID=203 CLIENT_HOSTNAME=client3 ./proxmox_vpc.sh create_vm
```

## Testing

Once both VMs are running, verify the setup from inside the client VM:

```bash
# Run this inside the client VM:

## Test connectivity to the router:
ping -c 3 10.99.0.1

## Test internet access through the router:
ping -c 3 1.1.1.1

## Test DNS resolution:
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
