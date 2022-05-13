---
title: "Proxmox part XX: virtualized nftables router"
date: 2022-05-10T00:02:00-06:00
tags: ['proxmox']
draft: true
---

Let's make a network router/firewall for the home LAN, with nftables,
inside of a Proxmox KVM virtual machine, with four physical ethernet
jacks passed into the VM's control.

## Hardware

The Proxmox server hardware used for testing is the [HP thin client
t740](https://www.servethehome.com/hp-t740-thin-client-review-tinyminimicro-with-pcie-slot-amd-ryzen).
This unit has a single PCIe slot, and it is populated with an Intel
i350-T4 (Dell OEM) network adapater with four physical ethernet jacks.
There is also one on-motherboard ethernet jack (Realtek) for a total
of five NICs.

Proxmox is installed using the on-board Realtek NIC as the only
interface bonded to `vmbr0` (the default public network bridge in
Proxmox). Instead, the four ports on the i350-T4 are passed directly
to the VM via IOMMU. This means the VM is totally in control of these
four physical NICs, and Proxmox is hands off. The Realtek NIC
(`enp2s0f0` bonded to `vmbr0`) will only be used to access the Proxmox
admin GUI and API. The i350 ports will be used as the new router (WAN,
LAN, OPT1, OPT2).

Technically, the i350-T4 should be capable of SRIOV, which would allow
the four ports to be split into several virtual interfaces (called
"functions") mapped to more than four VMs at the same time. However, I
could not get this to work, as it appears that the Dell variety of
this NIC disables SRIOV (doh! double check it when you buy it if you
want this feature!). However, for this project, SRIOV is unnecessary
and overkill, as the entire card will only need to be passed to one VM
(the router), and this is fully supported.

In addition to the physical network ports, a second virtual bridge
(`vmbr1`) is used to test routing to other virtual machines in the
VM_ID 100->199 block. If you don't have a machine with extra NICs (or
if it does not support IOMMU), you can still play along here, but
using the router for VMs and containers inside Proxmox only. (Maybe
you could technically make a router using VLANs with only one NIC, but
this is outside the scope of this post.)

## Create the VM

Arch Linux seems like a good choice for a router because it has the
latest kernel, and therefore the latest nftables version. Use the Arch
Linux template created in [part 5](05-kvm-templates)
(`TEMPLATE_ID=9000`):

```env
## export the variables needed by proxmox_kvm.sh:
export TEMPLATE_ID=9000
export VM_ID=100
export VM_HOSTNAME=router
VM1_BRIDGE=vmbr1
VM1_IP=192.168.1.1
```

```bash
./proxmox_kvm.sh clone
```

## Add a virtual network interface to VM bridge vmbr1

Add a second network interface to act as the gateway for the VM_ID
100->199 block on the vmbr1 network bridge:

```bash
qm set ${VM_ID} \
   --net1 "virtio,bridge=${VM1_BRIDGE}" \
   --ipconfig1 ip=${VM1_IP}/24
```

## Add the four physical NICs to the VM

On the Proxmox host, the i350-T4 shows up as a single PCI device
divided into four separate PCI device functions in the output of
`lspci`:

```
## example lspci excerpt
01:00.0 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
01:00.1 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
01:00.2 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
01:00.3 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
```

The left most column shows the PCI address of the device (`01:00`) and
the four device "functions" assigned to the four ethernet jacks: `.0`,
`.1`, `.2`, `.3`. If you look at `ip link` you will see these four
devices as `enp1s0f0`, `enp1s0f1`, `enp1s0f2`, and `enp1s0f3`.

(Note: If you have a card that has enabled SRIOV, `lspci` may list
more "functions" than the number of physical ports. This allows you to
use the same physical ethernet jack with multiple VMs at the same
time. This is not the case for the the test hardware, as it does not
have SRIOV, so these functions map exactly 1:1 to the physical
ethernet jacks on the card being tested, and they are all being passed
into to the router VM for exclusive use.)

Assign all of these device functions to the VM with one command
specifying only the root PCI address (`01:00`; without the `.X`):

```bash
qm set ${VM_ID} -machine q35 -hostpci0 01:00,pcie=on
```

Once you turn on the VM, you will find that `ip link` no longer shows
these devices on the Proxmox host, because they have been transferred
into the VM's control.

## Make an initial snapshot

You're about to start the router VM for the first time, but before you
do, make a snapshot. This way you will be able to rollback to a
completely fresh state later if you need to, without needing to
reclone and reconfigure the VM:

```bash
qm snapshot ${VM_ID} init
```

## Start the VM

```bash
qm start ${VM_ID}
```

cloud-init will run the first time the VM boots. This will install the
QEMU guest agent, which may take a few minutes.

Wait a bit for the boot to finish, then find out what the vm0 (admin)
IP address is:

```bash
./proxmox_kvm.sh get_ip
```

(If you see `QEMU guest agent is not running` just wait a few more
minutes and try again. You can also find the IP address on the VM
summary page in the GUI once the guest agent is installed.)

Test that SSH works to the public WAN IP address (replace `x.x.x.x`
with the discovered IP address):

```bash
ssh root@x.x.x.x
```

After the first boot, cloud-init will finish package upgrades and
other tasks in the background. You should wait for these tasks to
finish before using the VM. Check the completion of these tasks by
running:

```bash
# Run this inside the VM shell to monitor cloud-init tasks:
cloud-init status -w
```

You can also find the full cloud-init log in
`/var/log/cloud-init-output.log` (inside the VM).

## Rename network interfaces

At this point you should be able to SSH into the VM, and you will find
six ethernet devices via `ip link` (`eth0`->`eth5`). Let's rename
these interfaces to make it easier to remember what they will be used
for:

 * `vm0` (originally `eth0`) - This is the *virtual* interface
   connected to the `vmbr0` bridge (the public Proxmox VM bridge) -
   this interface is primarily for administration purposes only. This
   interface will be configured by an external DHCP server that you
   provide.
 * `vm1` (originally `eth1`) - This is the *virtual* interface
   connected to the `vmbr1` bridge (the private VM bridge serving the
   VM_ID 100->199 block.) By convention, the `vmbr1` bridge will use
   the `192.168.1.1/24` network, and this VM will have the IP address
   of `192.168.1.1`.
 * `wan` (originally `eth2`) - The inner most *physical* port on the
   i350-T4 - this is the public wide-area network (ie. the internet)
   interface of the router. This interface will be configured by
   external DHCP.
 * `lan` (originally `eth3`) - The second inner most *physical* port
   on the i350-T4 - this is the private local-area network interface
   of the router (ie. the home LAN). This will have a static IP
   address of `192.168.100.1` and will run a DHCP server for the
   `192.168.100.1/24` network, serving the home LAN.
 * `opt1` originally (`eth4`) - The second outer most *physical* port
   on the i350-T4 - this is an additional private network port
   (optional) with a static IP address of `192.168.101.1`.
 * `opt2` originally (`eth5`) - The outer most *physical* port on the
   i350-T4 - this is an additional private network port (optional)
   with a static IP address of `192.168.102.1`.

Find the MAC addresses for each of the cards. *Run all of the
following from inside the router VM*. Gather the four MAC addresses
into the temporary variables `MAC1`->`MAC4`:

```env
# Run this inside the router VM:
WAN_MAC=$(ip link show eth2 | grep "link/ether" | awk '{print $2}')
LAN_MAC=$(ip link show eth3 | grep "link/ether" | awk '{print $2}')
OPT1_MAC=$(ip link show eth4 | grep "link/ether" | awk '{print $2}')
OPT2_MAC=$(ip link show eth5 | grep "link/ether" | awk '{print $2}')
echo
echo "WAN  (physical)       : ${WAN_MAC}"
echo "LAN  (physical)       : ${LAN_MAC}"
echo "OPT1 (physical)       : ${OPT1_MAC}"
echo "OPT2 (physical)       : ${OPT2_MAC}"
```

Double check that the printed variables contain the correct MAC
addresses.

Create the network configuration for the four i350-T4 ports:

```bash
cat <<EOF > /etc/udev/rules.d/10-network.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${WAN_MAC}", NAME="wan"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${LAN_MAC}", NAME="lan"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OPT1_MAC}", NAME="opt1"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OPT2_MAC}", NAME="opt2"
EOF

cat <<EOF > /etc/netplan/60-i350-t4.conf
network:
    version: 2
    ethernets:
        wan:
            dhcp4: true
            match:
                macaddress: ${WAN_MAC}
            set-name: wan
        lan:
            addresses:
            - 192.168.100.1/24
            match:
                macaddress: ${LAN_MAC}
            nameservers:
                addresses:
                - 192.168.1.1
                search:
                - lan
            set-name: lan
        opt1:
            addresses:
            - 192.168.101.1/24
            match:
                macaddress: ${OPT1_MAC}
            nameservers:
                addresses:
                - 192.168.101.1
                search:
                - opt1
            set-name: opt1
        opt2:
            addresses:
            - 192.168.102.1/24
            match:
                macaddress: ${OPT2_MAC}
            nameservers:
                addresses:
                - 192.168.102.1
                search:
                - opt2
            ignore-carrier: true
            set-name: opt2
EOF
```

The virtual interfaces are listed in `/etc/netplan/50-cloud-init.yaml`
and are generated by cloud-init, however you can edit this file to
rename them and the changes will persist:

```bash
# Run this inside the router VM:
sed -i \
    -e 's/set-name: eth0/set-name: vm0/' \
    -e 's/set-name: eth1/set-name: vm1/' \
    /etc/netplan/50-cloud-init.yaml
```

Reboot the VM for the new device names to take effect and double check
with `ip link`.

```bash
reboot
```

And SSH back in again once it reboots.

## Install dnsmasq DHCP server

You will need a DHCP server for the `lan` and `vm0` interfaces.

Install dnsmasq, and create the config files:

```bash
# Run this inside the router VM:
( set -e
if ! command -v dnsmasq >/dev/null; then pacman -S --noconfirm dnsmasq; fi

cat <<EOF > /etc/dnsmasq-vm1.conf
interface=vm1
domain=vm1
bind-interfaces
listen-address=192.168.1.1
port=0
dhcp-range=192.168.1.10,192.168.1.250,255.255.255.0,1h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
EOF

cat <<'EOF' > /etc/systemd/system/dnsmasq@.service
[Unit]
Description=dnsmasq for %i
Documentation=man:dnsmasq(8)
After=network.target
Before=network-online.target nss-lookup.target
Wants=nss-lookup.target

[Service]
ExecStartPre=/usr/bin/dnsmasq -C /etc/dnsmasq-%i.conf --test
ExecStart=/usr/bin/dnsmasq -C /etc/dnsmasq-%i.conf -d --user=dnsmasq --pid-file
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
PrivateDevices=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dnsmasq@vm1.service
)
```

## Install dnscrypt-proxy DNS server

```bash
# Run this inside the router VM:
if ! command -v dnscrypt-proxy >/dev/null; then pacman -S --noconfirm dnscrypt-proxy; fi
sed -i \
  -e "s/^listen_addresses =.*/listen_addresses = ['127.0.0.1:53','[::1]:53','192.168.1.1:53','192.168.100.1:53']/" \
  -e "s/^# server_names =.*/server_names = ['cloudflare']/" \
  /etc/dnscrypt-proxy/dnscrypt-proxy.toml
```

## Install nftables

Install and enable nftables:

```bash
# Run this inside the router VM:
pacman -S --noconfirm nftables
systemctl enable --now nftables
```

nftables comes installed with a pre-configured firewall ruleset in
`/etc/nftables.conf`. You can look at the current configuration with:

```bash
# Run this inside the router VM:
nft list ruleset
```

The default ruleset is a basic configuration that drops all incoming
packets except for SSH and ICMP for ping. This configuration is not
yet suitable for a router, but provides a reasonble place to start.


## Create nftables rules

Overwrite the `/etc/nftables.conf` and provide the new nftables
configuration:

```bash
## Run inside the router VM:

cat <<EOF > /etc/sysctl.d/ip_masquerade.conf
net.ipv4.ip_forward = 1
EOF

cat <<'EOF' > /etc/nftables.conf
#!/usr/bin/nft -f

define VM1_CIDR = 192.168.1.1/24
define LAN_CIDR = 192.168.100.1/24
define OPT1_CIDR = 192.168.101.1/24
define OPT2_CIDR = 192.168.102.1/24

define WAN_INTERFACE = { vm0 }
define PRIVATE_INTERFACES = { vm1, lan, opt1, opt2 }

define VM0_ACCEPTED_TCP = { 22 }
define VM1_ACCEPTED_TCP = { 53 }
define VM1_ACCEPTED_UDP = { 53, 67 }

define PUBLIC_ACCEPTED_ICMP = {
    destination-unreachable,
    router-advertisement,
    time-exceeded,
    parameter-problem }
define PUBLIC_ACCEPTED_ICMPV6 = {
    destination-unreachable,
    packet-too-big,
    time-exceeded,
    parameter-problem,
    nd-router-advert,
    nd-neighbor-solicit,
    nd-neighbor-advert }

## Remove all existing rules:
flush ruleset

## filter IPv4 and IPv6:
table inet filter {
  set public_accepted_icmp { type icmp_type; elements = $PUBLIC_ACCEPTED_ICMP }
  set public_accepted_icmpv6 { type icmpv6_type; elements = $PUBLIC_ACCEPTED_ICMPV6 }

  set private_interfaces { type iface_index; elements = $PRIVATE_INTERFACES }
  set vm0_accepted_tcp { type inet_service; flags interval; elements = $VM0_ACCEPTED_TCP }
  set vm1_accepted_tcp { type inet_service; flags interval; elements = $VM1_ACCEPTED_TCP }
  set vm1_accepted_udp { type inet_service; flags interval; elements = $VM1_ACCEPTED_UDP }

  ## To ban a host for one day: nft add element ip filter blackhole { 10.0.0.1 }
  set blackhole { type ipv4_addr; flags timeout; timeout 1d; }

  counter wan-egress { }
  counter wan-ingress { }

  chain input {
    type filter hook input priority filter
    policy drop

    ct state invalid drop comment "early drop of invalid connections"
    iif lo accept comment "allow from loopback"
    iif $WAN_INTERFACE counter name wan-ingress;
    ip saddr @blackhole drop comment "drop banned hosts"
    ct state {established, related} accept comment "allow tracked connections"

    # Allow only a subset of ICMP messages:
    iif @private_interfaces ip protocol icmp accept comment "Allow private unrestricted ICMP"
    iif @private_interfaces ip6 nexthdr icmpv6 accept comment "Allow private unrestricted ICMPv6"
    iif $WAN_INTERFACE ip protocol icmp icmp type @public_accepted_icmp limit rate 100/second accept comment "Allow some ICMP"
    iif $WAN_INTERFACE ip6 nexthdr icmpv6 icmpv6 type @public_accepted_icmpv6 limit rate 100/second accept comment "Allow some ICMPv6"

    tcp dport @vm0_accepted_tcp iifname vm0 ct state new log prefix "Admin connection on VM0:" accept
    tcp dport @vm1_accepted_tcp iifname vm1 ct state new accept
    udp dport @vm1_accepted_udp iifname vm1 ct state new accept

    iif $WAN_INTERFACE drop comment "drop all other packets from WAN"
    pkttype host limit rate 5/second counter reject with icmpx type admin-prohibited comment "Reject all other packets with rate limit"
    counter
  }
  chain forward {
    type filter hook forward priority filter; policy drop;
    ct state invalid drop comment "early drop of invalid connections"
    ct state {established, related} accept comment "allow tracked connections"
    iif @private_interfaces oif $WAN_INTERFACE accept comment "allow private network WAN egress"
  }
  chain output {
    type filter hook output priority filter; policy accept;
    oif $WAN_INTERFACE counter name wan-egress
  }
}

table ip nat {
  set private_interfaces { type iface_index; elements = $PRIVATE_INTERFACES }
  chain prerouting {
    type filter hook output priority filter; policy accept;
  }
  chain postrouting {
    type nat hook postrouting priority srcnat;
    iif @private_interfaces oif $WAN_INTERFACE masquerade
  }
}
EOF

sysctl --load /etc/sysctl.d/ip_masquerade.conf >/dev/null
systemctl restart nftables
```

Verify the new ruleset:

```bash
# Run this inside the router VM:
nft list ruleset
```

If you run into problems where the configuration is invalid, you can
debug the errors by running:

```bash
# Run this inside the router VM:
## This won't reload the firewall, but will simply check the syntax:
nft -f /etc/nftables.conf -c
```
