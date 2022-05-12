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

## Start the VM

```bash
qm start ${VM_ID}
```

cloud-init will run the first time the VM boots. This will install the
Qemu guest agent, which may take a few minutes.

Wait a bit for the boot to finish, then find out what the vm0 (admin)
IP address is:

```bash
./proxmox_kvm.sh get_ip
```

(If you see `QEMU guest agent is not running` just wait a few more
minutes and try again.)

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

Now create the device udev rules to rename the devices on every boot:

```bash
# Run this inside the router VM:
cat <<EOF > /etc/udev/rules.d/10-network.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${WAN_MAC}", NAME="wan"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${LAN_MAC}", NAME="lan"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OPT1_MAC}", NAME="opt1"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OPT2_MAC}", NAME="opt2"
EOF
```

The virtual interfaces cannot be renamed in the same way, because they
were created by cloud-init. They are defined in
`/etc/netplan/50-cloud-init.yaml`. You can rename them this way:

```bash
# Run this inside the router VM:
sed -i \
    -e 's/set-name: eth0/set-name: vm0/' \
    -e 's/set-name: eth1/set-name: vm1/' \
    /etc/netplan/50-cloud-init.yaml
```

Reboot the VM for the new device names to take effect and double check
with `ip link`.

