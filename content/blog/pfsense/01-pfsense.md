---
title: "How to configure a pfsense router with split VLANs"
url: "pfsense/pfsense"
date: 2023-11-08T11:46:03-07:00
---

TODO: anonymize the addresses and domains!

This example installation will use the ODroid H3 as the core pfsense
router for a home installation. This configuration includes an addon
card for a total of six 2.5Gbps Ethernet network controllers (NICs).

## Network design

The six NICs on the odroid will be used like this:

 * port 1: WAN - wide area network, ie. the internet.
 * port 2: LAN - local area network, ie. family computers and devices.
 * port 3: OPT1 - multiple vlan carrier
 * port 4: OPT2 - multiple vlan carrier
 * port 5: OPT3 - multiple vlan carrier
 * port 6: OPT4 - multiple vlan carrier

The physical ports only cover the usage for a simple WAN and LAN type
network, this configuration also supports segmented networks for
consumer devices (IOT), a separate homelab network (APPS), and one for
home assistant (HASS).

The following VLANs are defined:

 * vlan 132: LAN (vlan to access the phyiscal LAN network)
 * vlan 133: IOT (Internet of Things)
 * vlan 134: APPS (Proxmox and Docker)
 * vlan 135: HASS (Home Assistant)

Any of the VLANs may be tagged to any multiple of the OPT vlan carrier
ports, depending on your needs, and where the wire is going to.

Each network is in charge of a `/24` address space :

 * LAN  `192.168.132.1/24` (`192.168.132.1` -> `192.168.132.255`)
 * IOT  `192.168.133.1/24` (`192.168.133.1` -> `192.168.133.255`)
 * APPS `192.168.134.1/24` (`192.168.134.1` -> `192.168.134.255`)
 * HAAS `192.168.135.1/24` (`192.168.135.1` -> `192.168.135.255`)

pfsense will act as the DNS, DHCP, and firewall services for each of
these networks.

## ODroid H3 specfic needs

The ODroid needs a specific realtek driver that is not included on the
installation media. This driver can be installed from the package
repository. TODO: document where this is.

The ODroid is just a computer with six NICs, it is *not* a network
switch. Without a builtin switch, pfsense will create VLANs on NICs
that operate as *trunk* ports. This means you cannot attach any client
without first having configured the VLAN *on the client* NIC. You
should never allow untrusted devices to conneect to a trunk port, so
you need to use a managed switch.

The first two ports of the ODroid H3 are used for WAN and LAN, and
these ports are not using any VLANs. The other four ports we will use
VLANs with, so when you look to buy a switch you need to get one that
has at least eight ports. Remember that the switch must be a *managed*
switch, in order to be able to configure the vlans *on the switch
itself*. 1Gb managed swiches can be found very cheap for about $20 or
so (eg. Netgear GS305E). 2.5Gb managed switches are bit more rare, but
check out the "Sodola 9 port 2.5G Managed Ethernet Switch".

You will need to configure the ports on the managed switch in pairs,
1+2, 3+4, 5+6, 7+8, configuring each pair with the same VLAN ids.
You'll plug one of each pair into pfsense, and the other one to the
network leg its going to. A managed switch can configure a port with a
"Default" vlan, so that any untagged traffic will get tagged
automatically by the switch, as well as configuring additional allowed
tagged vlans (blocking any vlans that are not configured).

## Install pfsense

Download the .iso, `dd` it to a flash drive, plug a keyboard and mouse
into the router, boot it, and install pfsense.

## Reset to factory defaults

In case you already have an existing pfsense system, and you want to
start from scratch, you don't need to reinstall, you can simply reset
it to factory defaults, and then you'll have a fresh start with which
to follow the rest of this guide. You can choose option `4) Reset to
factory defaults` in the console menu to do this.

## Initial console setup

In the console, choose `1) Assign interfaces`:

It will print out a list of all your network interfaces. In the case
of the ODroid H3 there are six interfaces named
`re0`,`re1`,`re2`,`re3`,`re4`, and `re5`.

`Do VLANs need to be setup first?`

This first question asks you whether to setup VLANs. **For now, you
need to choose No (press `n` and press Enter.)** as you will set it up
later using the web dashboard.

`Enter the WAN interface name or 'a' for auto-detection`

Enter `re0` for the WAN device (this may be a different name depending
on your hardware)

`Enter the LAN interface name or 'a' for auto-detection`

Enter `re1` for the LAN device.

`Enter the Optional 1 interface name or 'a' for auto-detection`

You will enter the rest of the interfaces for all the optional ports:
`re2`, `re3`, `re4`, `re5`.

## Set the LAN address

In the console, choose `2) Set interface(s) IP address`:

It will print out a list of the interfaces you just created. Choose
`2 - LAN (re1 - static)`.

`Configure IPv4 address LAN interface via DHCP? (y/n)`

The LAN interface should use a static IP address, so you should choose
`n` to disable the LAN interface DHCP setting (ie. pfsense should *be*
the LAN DHCP server, and not get its IP from any other DHCP server).

`Enter the new LAN IPv4 address:`

Enter the address: `192.168.132.1`

`Enter the new LAN IPv4 subnet bit count (1 to 32):`

Enter the bit count: `24`

`For a WAN, enter the new LAN IPv4 upstream gateway address. For a LAN, press <ENTER> for none:`

Press Enter for none (there is no upstream LAN gateway)

`Configure IPv6 address LAN interface via DHCP6? (y/n)`

Choose `n` to disable the LAN interface IPv6 DHCP setting (again,
pfesense has a static ip and will *be* the DHCP server)

`Enter the new LAN IPv6 address. Press <ENTER> for none:`

Press Enter for none (IPv6 will not be necessary for this
installation.)

`Do you want to enable the DHCP server on LAN (y/n)`

Choose `y` (pfsense will *be* the DHCP server)

`Enter the start address of the IPv4 client address range:`

Enter the start address for DHCP range: `192.168.132.50`

This reserves some room at the start from the 1->49 range for static
ip address assignments.

`Enter the end address of the IPv4 client address range:`

Enter the end address for the DHCP range: `192.168.132.250`

This too reserves some room at the end for static assignments.

`Do you want to revert to HTTP as the webConfiguration protocol? (y/n)`

Say `y` for now, to use unencrypted HTTP. But you may want to get a
real certificate from ACME Let's Encrypt, and then you can turn on
HTTPS later on.

Finally the setup should conclude, and print the web configurator url,
which in the demo case is: `http://192.168.132.1`

You can now unplug the keyboard and monitor from the router as they
won't be needed again during normal usage.

## Login to the web console

Connect a client machine into the LAN port of the router, and you
should easily acquire a IPv4 address via DHCP. Assuming you're the
first one to connect, the address you receive should be
`192.168.132.50`.

On the client, open a web browser to `http://192.168.132.1`.

Login with the default credentials:

 * username: `admin`
 * password: `pfsense`

Go through the initial setup wizard:

 * Enter the hostname: `router`
 * Enter the domain: `gtown.thewooskeys.com`
 * Enter the primary DNS server: `1.1.1.1` (or whatever you prefer)
 * Enter the secondary DNS server: `1.0.0.1` (or whatever you prefer)
 * Make sure that your browser does not automatically fill any saved
   passwords into any of the fields (eg. `PPTP password`), your
   browser does not understand the context it is in, and it likes to
   fill in the incorrect value here (which likely should remain empty
   instead).
 * *Important* set a secure admin passphrase
 * Click the Check for updates button and then Finish the wizard.

## Reboot the router

It is recommended to reboot after the initial config, this will help
to get the services started correctly, including the DNS resolver for
the LAN. Under `Diagnostics` choose `Reboot` and wait for the router
to reboot.

## Enable the SSH server

It can be handy to be able to SSH into the router, but you need to be
careful to configure it to require keys (no passwords!) and you need
to keep your SSH key safe (password protected and/or use a hardware
token).

Enable SSH:

 * Click on `System`
 * Click on `Advancded`
 * Click on `Enable Secure Shell`
 * Select from the `SSHd key only` option and choose `Public Key
   Only`.
 * Click `Save`

Add your SSH keys:

 * On your workstation, copy the contents of your SSH public key file
   (`~/.ssh/id_rsa.pub`) or grab it from your agent (`ssh-add -L`). If
   you haven't got a key, use `ssh-keygen`.
 * Click on `System`
 * Click on `User Manager`
 * Click the edit button on the `admin` user.
 * Paste your ssh pub key into the field `Authorized SSH Keys`.
 * Click `Save`.

## Enable the OPT interfaces

Click `Interfaces` and then `OPT1`.

 * Click on `Enable Interface`
 * Click `Save`.
 * Click `Apply Changes`.

Do the same thing for interfaces `OPT2`, `OPT3`, `OPT4`.

## Create IOT VLAN

Click `Interfaces`, then `Assignments`, then click on the `VLANs` tab.

 * Click `Add`

Enter the new VLAN configuration:

 * Parent Interface: `opt1`
 * VLAN tag: 133
 * VLAN priority: 0 (its the default, you can leave it empty)
 * Description: `IOT`

 * Click `Save`

Click on the `Interface Assignments` tab

 * Find the line at the bottom `Available network ports`
 * Choose from the list: `VLAN 133 on re2 - opt1 (IOT)`
 * Click on the `Add` button on the right

This will create a new interface named `OPT5`. Rename the interface
now to `IOT`:

 * Click on `OPT5`.
 * Click on `Enable interface`
 * Enter the description: `IOT`
 * Enter the IPv4 Configuration Type: `Static IPv4`
 * Enter the IPv4 Address: `192.168.133.1`
  * Make sure to change the subnet size to `/24` (not `/32`).
 * Click `Save`
 * Click `Apply Changes`
 * Notice that the Interface is automatically renamed `IOT (re2.133)`
   on its configuration page to denote the physical interface and the
   vlan id.

Turn on the DHCP server for the `IOT` VLAN:

 * Click on `Services`
 * Click on `DHCP Server`
 * Click on the `IOT` tab
 * Click `Enable DHCP server on IOT interface`
 * Enter the IP address pool range:
   * Start: `192.168.133.10`
   * End: `192.168.133.250`
 * Enter the domain name: `iot.gtown.thewooskeys.com`
 * Click `Save`

## Test the IOT VLAN

Connect a client to the switch port that is connected to pfsense port
3 (`re2`) (which is now tagged for the `IOT` vlan). You should easily
connect with DHCP, and be assigned an IP address in the
`192.168.133.0/24` network.

