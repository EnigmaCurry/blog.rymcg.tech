---
title: "Proxmox part 2: Networking"
date: 2022-05-04T00:01:00-06:00
tags: ['proxmox']
---

In [part 1](/blog/proxmox/01-install), we installed a fresh Proxmox
server, configured SSH, updated repositories, and configured a basic
node firewall.

In this post, we will continue setting up our Proxmox server's
network.

## Use bridge networking for private networks

By default, Proxmox uses bridge networking, which is very simple to
setup, assuming you already have a LAN and an existing DHCP server and
gateway on it. With bridge networking, you can use a single network
interface with all of the virtual machines accessible through it. Each
VM will have a unique virtual MAC address, and each will receive a
unique IP address from your DHCP server. All the VMs become
discoverable on the network, just like any other machine on your LAN.

By default, Proxmox creates a single bridge network, named `vmbr0`,
and this is connected to the management interface, and it is assumed
you will connect this to your LAN.

{{<img src="/img/proxmox/bridge-network.png" alt="The default Bridge network, vmbr0">}}

If you are able to use bridge networking, great! Nothing more to do
here. If you have run out of IP addresses though, read on!

## Use Network Address Translation (NAT) if you have limited IP addresses

If you are deploying to the internet, you likely have only a finite
number of IP addresses, or possibly, only one.

When you have limited IP addresses, you can use Network Address
Translation (NAT) to let several virtual machines access the network
using the same IP address. Source NAT (SNAT) or IP Masquerading
provides private VMs outbound/egress to the WAN/internet.
Inbound/ingress "port forwarding" is called destintation NAT (DNAT),
and with this you have multiple servers all on one IP address, but
each using a unique port number from the host, forwarded directly to
the private service.

Proxmox has no builtin support, through the dashboard, for configuring
either kinds of NAT. However, because Proxmox is based on Debian
Linux, we can configure the NAT rules with `iptables` through the
command line.

If you want to enable NAT, here are the steps:

 * Connect to the pve node through SSH, logging in as the `root` user.
 * Download the `proxmox_nat.sh` configuraton script, and make it
   executable:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_nat.sh

chmod +x proxmox_nat.sh
```

 * The script has a menu interface:

```
NAT bridge tool:
 * Type `i` or `interfaces` to list the bridge interfaces.
 * Type `c` or `create` to create a new NAT bridge.
 * Type `l` or `list` to list the NAT rules.
 * Type `n` or `new` to create some new NAT rules.
 * Type `d` or `delete` to delete some existing NAT rules.
 * Type `?` or `help` to see this help message again.
 * Type `q` or `quit` to quit.
```

 * Type `i` (and press Enter) to list all the bridge interfaces (you
   can see I have created some additional NAT bridges already):

```
Enter command (for help, enter `?`)
: i

Currently configured bridges:
BRIDGE  NETWORK         COMMENT
vmbr0   10.13.13.11/24
vmbr1   10.99.0.2/24
vmbr50  172.16.13.2/24  pfsense MGMT only
vmbr55  10.55.0.1/24    NAT 10.55.0.1/24 bridged to vmbr0
```

 * Type `c` (and press Enter) to create a new interface:

```
Enter command (for help, enter `?`)
: c

Configuring new NAT bridge ...
Enter the existing bridge to NAT from
: vmbr0
Enter a unique number for the new bridge (dont write the vmbr prefix)
: 56

Configuring new interface: vmbr56
Enter the static IP address and network prefix in CIDR notation for vmbr56:
: 10.56.0.1/24

## DEBUG: IP_CIDR=10.56.0.1/24
## DEBUG: IP_ADDRESS=10.56.0.1
## DEBUG: NETMASK=

Enter the description/comment for this interface
: NAT 10.56.0.1/24 bridged to vmbr0
Wrote /etc/network/interfaces
Activated vmbr56
```

 * Type `i` again and see the new interface `vmbr56` has been created:

 ```
 Enter command (for help, enter `?`)
: i

Currently configured bridges:
BRIDGE  NETWORK         COMMENT
vmbr0   10.13.13.11/24
vmbr1   10.99.0.2/24
vmbr50  172.16.13.2/24  pfsense MGMT only
vmbr55  10.55.0.1/24    NAT 10.55.0.1/24 bridged to vmbr0
vmbr56   10.56.0.1/24   NAT 10.56.0.1/24 bridged to vmbr0
 ```

 * Type `n` to create create a new NAT rule:

```
Enter command (for help, enter `?`)
: n

Defining new port forward rule:
Enter the inbound interface
: vmbr0
Enter the protocol (tcp, udp)
: tcp
Enter the inbound Port number
: 2222
Enter the destination IP address
: 10.56.0.2
Enter the destination Port number
: 22
INTERFACE  PROTOCOL  IN_PORT  DEST_IP    DEST_PORT
vmbr0      tcp       2222     10.56.0.2  22
? Is this rule correct? (Y/n): y

? Would you like to define more port forwarding rules now? (y/N): n
Wrote /etc/network/my-iptables-rules.sh
Systemd unit already enabled: my-iptables-rules
NAT rules applied: /etc/network/my-iptables-rules.sh

## Existing inbound port forwarding (DNAT) rules:
INTERFACE  PROTOCOL  IN_PORT  DEST_IP    DEST_PORT
vmbr0      tcp       2222     10.56.0.2  22
```

 * Type `l` to list the current NAT rules, showing the rule you just
   added:

```
Enter command (for help, enter `?`)
: l

## Existing inbound port forwarding (DNAT) rules:
INTERFACE  PROTOCOL  IN_PORT  DEST_IP    DEST_PORT
vmbr0      tcp       2222     10.56.0.2  22
```

 * Type `d` to delete an existing NAT rule:

```
Enter command (for help, enter `?`)
: d

LINE#  INTERFACE  PROTOCOL  IN_PORT  DEST_IP    DEST_PORT
1      vmbr0      tcp       2222     10.56.0.2  22
Enter the line number for the rule you wish to delete (type `q` or blank for none)
: 1
Wrote /etc/network/my-iptables-rules.sh
Systemd unit already enabled: my-iptables-rules
NAT rules applied: /etc/network/my-iptables-rules.sh
No inbound port forwarding (DNAT) rules have been created yet.
```

 * Type `e` to enable or disable the systemd service that manages these rules:

 ```
Enter command (for help, enter `?`)
: e

The systemd unit is named: my-iptables-rules
The systemd unit is currently: enabled
? Would you like to enable the systemd unit on boot? (Y/n): y
Systemd unit enabled: my-iptables-rules
NAT rules applied: /etc/network/my-iptables-rules.sh
 ```

## The script

 * [You can download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/proxmox/proxmox_nat.sh)

{{< code file="/src/proxmox/proxmox_nat.sh" language="shell" >}}

## Systemd unit to manage NAT rules

The script includes a systemd unit that is setup to add the DNAT
(ingress) rules on every system boot.

Here are the relevant files, whose paths are all declared at the top
of the script:

```env
SYSTEMD_UNIT="my-iptables-rules"
SYSTEMD_SERVICE="/etc/systemd/system/${SYSTEMD_UNIT}.service"
IPTABLES_RULES_SCRIPT="/etc/network/${SYSTEMD_UNIT}.sh"
```

 * `SYSTEMD_UNIT` is the name of the systemd service that is started.
   You can interact with it with `systemctl`:

```bash
$ systemctl status my-iptables-rules
● my-iptables-rules.service - Load iptables ruleset from /etc/network/my-iptables-rules.sh
     Loaded: loaded (/etc/systemd/system/my-iptables-rules.service; enabled; preset: enabled)
     Active: active (exited) since Wed 2023-11-22 16:05:48 MST; 6h ago
    Process: 469722 ExecStart=/etc/network/my-iptables-rules.sh (code=exited, status=0/SUCCESS)
        CPU: 8ms

Nov 22 16:05:48 pve systemd[1]: Starting my-iptables-rules.service - Load iptables ruleset from /…s.sh...Nov 22 16:05:48 pve my-iptables-rules.sh[469722]: Error: PORT_FORWARD_RULES array is empty!
Nov 22 16:05:48 pve systemd[1]: Started my-iptables-rules.service - Load iptables ruleset from /e…les.sh.Hint: Some lines were ellipsized, use -l to show in full.
```

The output `Error: PORT_FORWARD_RULES array is empty!` is normal when
you have not yet defined any DNAT rules (ie. all ports are blocked).
If you need to see the full log output, use `journalctl`:

```
journalctl --unit my-iptables-rules
```

 * `SYSTEMD_SERVICE` is the full path to the systemd service config
   file, (and which is automatically created by the script).

```
## You don't need to copy this, this is just an example of what
## the script automatically creates for you:
[Unit]
Description=Load iptables ruleset from /etc/network/my-iptables-rules
ConditionFileIsExecutable=/etc/network/my-iptables-rules
After=network-online.target

[Service]
Type=forking
ExecStart=/etc/network/my-iptables-rules
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=network-online.target
```

The `WantedBy` config will ensure the service is started on boot.

 * `IPTABLES_RULES_SCRIPT` is the path to the NAT rules
   configuration/script, (and which is automatically created by the
   script). The systemd service calls this script to add the NAT
   rules, on boot. You can also call the script yourself anytime. When
   the script is executed, *all* of the existing DNAT rules are purged
   (they are all tagged `Added by ${IPTABLES_RULES_SCRIPT}`, and so
   are deleted based on this same tag.). New rules are then created
   based on the `PORT_FORWARD_RULES` variable in the current
   `IPTABLES_RULES_SCRIPT`.

## Manage bridges from the dashboard

Although you cannot manage the NAT rules from the dashboard, you can
add or remove the bridges:

{{<img src="/img/proxmox/nat-bridges.png" alt="Proxmox dashboard shows all the NAT bridges, you can easily delete them from here">}}

## Creating VMs with NAT

With bridge networking, VMs can query a DHCP server to get an IP
address. When using a private NAT network, there is no DHCP server (by
default) that can be contacted. Therefore, you will need to configure
a static IP address and gateway for each VM:

{{<img src="/img/proxmox/cloud-init-static-ip-address.png" alt="VM cloud-init setting a static IP address and gateway">}}

Configure the virtual network card to connect to the correct bridge:

{{<img src="/img/proxmox/vm-network-bridge.png" alt="A VM selecting the bridge to connect the virtual ethernet cable to">}}

## Adding a DHCP server

If you want to add a DHCP server to your NAT bridge, you can use
something simple like dnsmasq. You'll need to create a VM with a
static IP.

For example, suppose:

 * `10.1.1.1` is the Proxmox host on `vmbr1` (this is the gateway)
 * `10.1.1.2` is a VM with a static IP, tasked with running dnsmasq
   (this is the DHCP server)

```bash
# Run this on the VM running on 10.1.1.2:
apt update
apt install dnsmasq
```

Edit the `/etc/dnsmasq.conf` config file on the VM:

```
## Example /etc/dnsmasq.conf file for running a DHCP server:
interface=eth0
except-interface=lo
domain=vm1
bind-interfaces
listen-address=10.1.1.2
server=::1
server=127.0.0.1
dhcp-range=10.1.1.10,10.1.1.250,255.255.255.0,1h
dhcp-option=3,10.1.1.1
dhcp-option=6,10.1.1.1
```

Save the file, and restart dnsmasq:

```
systemctl enable --now dnsmasq
systemctl restart dnsmasq
```

If you now boot another VM on the same bridge (`vmbr1`), and if its
configured for DHCP, it should get an ip from the dnsmasq server, and
create a route through the proxmox host `10.1.1.1`. Now you won't have
to set any more static IPs.
