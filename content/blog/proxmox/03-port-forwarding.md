---
title: "Proxmox part 3: Port Forwarding to a Virtual Proxmox KVM"
date: 2021-07-31T00:02:00-06:00
tags: ['proxmox']
---

## Introduction

In [Part 1](/blog/proxmox/01-virtual-proxmox/) of this series, you installed a
Virtual Proxmox server in a libvirt virtual machine (with the GUI tool
`virt-manager`), and you chose the network selection of type `Virtual
Network 'default': NAT`. This type of network only allows traffic from another
(virtual) machine on the same network (`'default'`), including from your host
workstation (libvirt has created a virtual network device, on the host
workstation, with an IP address in the same subnet as the VM running Proxmox).
No external traffic is allowed to this network (ie. from your LAN), because, by
default, there are no external routes created for it.

The NAT network type provides pretty good default security for a development
environment, where you only want access from your workstation. However, you may
soon wish to deliberately expose some services to other machines on your LAN, or
even to the Internet.

When exposing the Proxmox dashboard, it is important to install a valid TLS
certificate, and stop using the default self-signed certificate created on first
install. (Remember how you had to tell your browser that the certificate was
OK?) Proxmox has the ability to generate a valid certificate, using [Let's
Encrypt](https://letsencrypt.org/) with ACME [DNS-01 challenge
type](https://letsencrypt.org/docs/challenge-types/). This allows you to create
a valid browser-trusted TLS certificate, even if your host system itself is
behind another NAT firewall (which is the typical home Interet configuration,
with no external ports opened, which excludes the use of ACME HTTP or TLS
challenge types).

If you follow the suggestions in this post for exposing services, you are
changing the role of your workstation: it is now a a hybrid workstation and
server (for your LAN and/or the Internet).

## Setup firewall and routes on host

Create the libvirt hooks directory on the native libvirt host:

```
# This directory didn't exist for me, so I had to create it:
sudo mkdir -p /etc/libvirt/hooks
```

Create a new libvirt hooks file, `/etc/libvirt/hooks/qemu`:

```
#!/bin/bash
# /etc/libvirt/hooks/qemu

# Forward ports for Proxmox
# See https://wiki.libvirt.org/page/Networking
# Find your actual Proxmox VM IP address and put it here:
PROXMOX_IP=192.168.122.X
# Associative array of TCP host ports to TCP proxmox ports:
PROXMOX_TCP_PORTS=([8006]=8006 [2222]=22)

# Port forwarding for the Proxmox VM
if [ "${1}" = "Proxmox" ]; then
   for key in "${!PROXMOX_TCP_PORTS[@]}";
   do
       host_port=${key}
       proxmox_port=${PROXMOX_TCP_PORTS[key]}
       if [ "${2}" = "stopped" ] || [ "${2}" = "reconnect" ]; then
           /sbin/iptables -D FORWARD -o virbr0 -p tcp -d $PROXMOX_IP \
               --dport $proxmox_port -j ACCEPT
           /sbin/iptables -t nat -D PREROUTING -p tcp \
               --dport $host_port -j DNAT --to $PROXMOX_IP:$proxmox_port
       fi
       if [ "${2}" = "start" ] || [ "${2}" = "reconnect" ]; then
           /sbin/iptables -I FORWARD -o virbr0 -p tcp -d $PROXMOX_IP \
               --dport $proxmox_port -j ACCEPT
	       /sbin/iptables -t nat -I PREROUTING -p tcp \
               --dport $host_port -j DNAT --to $PROXMOX_IP:$proxmox_port
       fi
   done
fi
```

Edit the new hooks file, change the following:

 * `PROXMOX_IP` the value of this variable should be the IP address of your
   Proxmox Server VM. (The same as the `Hostname` for `proxmox` in your
   `~/.ssh/config`)
 * `PROXMOX_TCP_PORTS` is a translation map of TCP ports between your host and
   Proxmox. The example does the following:
   
   * Pass TCP host port `8006` directly to Proxmox TCP port `8006`. This is for
     the Proxmox dashboard.
   * Translate TCP host port `2222` to Proxmox TCP port `22`. This is for SSH
     access to the Proxmox server.
     
 * Note that this hook configures the *host* firewall, and only forwards
   packets, it does not do any filtering. Filtering is the role of the Proxmox
   firewall, which will be configured next.

Now restart the `libvirtd` service and the hook will automatically run. (You do
not need to restart the Proxmox VM).

## Configure the Proxmox firewall

You already turned on the Proxmox firewall in part 1 of this series, now you
need to add additional rules to allow access from outside your workstation:

 * Go to the Proxmox dashboard, click on the `Datacenter` in the `Server View`
   list.
 * Click on `Firewall` in the `Datacenter` view.
 * Click on `Add` to add a new firewall rule:
   * Click the `Enable` checkbox.
   * Click the `Macro` dropdown, and select `SSH`.
   * Optional: Enter a `Source` to filter by IP/Subnet range. (Note that Proxmox
     already allows the private virbr0 network by default [anti-lockout rule for your workstation], so you only need to
     filter the outside network.)
   * Click the `Add` button to add the new rule.
 * Click on `Add` to add another new firewall rule:
   * Click the `Enable` checkbox.
   * Click the `Protocol` dropdown, and select `tcp`.
   * Enter the `Dest. port` as `8006`.
   * Optional: Enter a `Source` to filter by IP/Subnet range. (Note that Proxmox
     already allows the private virbr0 network by default [anti-lockout rule for
     your workstation], so you only need to filter the outside network.)
   * Click the `Add` button to add the new rule.

## Test the firewall

Use a second computer on the same LAN as your workstation (ie. your home WiFi):

```bash
# Test access to the proxmox dashboard port forwarded from the workstation.
# Enter the LAN IP address of the workstation:
curl -k https://X.X.X.X:8006

# Test SSH access to port 2222 which forwards to the Proxmox port 22:
# Enter the LAN IP address of the workstation:
ssh -p 2222 root@X.X.X.X
```

Assuming it works, you should get an HTML response back from `curl` and the
`ssh` connection should connect and not hang (it is OK if it says `Permission
denied (publickey)`, because this shows that the connection itself is working.)

## Generate a valid TLS certificate

In order to generate a certificate from a private LAN, you need to use the ACME
DNS-01 challenge type, which requires you to control the DNS server for the
Internet domain the certificate is to be issued for. You can use a DNS host like
[DigitalOcean](https://digitalocean.com), which offers an API that Proxmox can
use to update DNS automatically to satisfy the requirements of the ACME DNS-01
challenge. This example will use DigitalOcean DNS.

### Setup DigitalOcean DNS

 * Go to [cloud.digitalocean.com](https://cloud.digitalocean.com) and go to your
   project's `Networking` page in the main sidebar menu.
 * Click on the `Domains` tab.
 * Add your domain if you haven't already.
 * Go to the `API` page in the main sidebar menu.
 * Click on the `Tokens/Keys` tab.
 * Click `Generate New Token`.
 * Enter `Proxmox ACME on [hostname]` for the name.
 * Select the `Write` scope.
 * Click `Generate Token`.
 * Copy the new `Personal access token`, it is only shown once. This is to be
   kept safe, as it can control your entire DigitalOcean (sub-)account.
 
### Setup Proxmox ACME

Configure the Proxmox Datacenter:

 * Go to the Proxmox dashboard, look under the `Server View`, click on the
   `Datacenter`.
 * Click on the `ACME` tab.
 * Under `Accounts` click the `Add` button.
 * Use the account name: `default`
 * Enter your real `E-Mail` address.
 * Select the `ACME Directory`: choose `Let's Encrypt V2` for the production
   certificate service.
 * Check the `Accept TOS` checkbox.
 * Click `Register`.
 * Under `Challenge Plugins`, click the `Add` button.
 * Enter the `Plugin ID`: `digitalocean` (or the name for your provider).
 * Select the `DNS API`: `DigitalOcean DNS`.
 * Enter the `DO_API_KEY`: (This is to be pasted from the `Personal access
   token` you copied from the DigitalOcean dashboard.)

Configure the Proxmox server node:

 * Look under the `Server View`, click on the Proxmox server node (underneath
   `Datacenter`).
 * Under `System`, click on `Certificates`.
 * Under `ACME`, click the `Add` button.
 * Change the `Challenge Type` to `DNS`.
 * Choose the `Plugin`: `digitalocean`
 * Enter the sub domain name you want to use for the Proxmox dashboard
   certificate (eg. `proxmox.example.com` if you own `example.com`)
 * Click the `Order Certificates Now` button.


### Configure DNS to use the hostname of the certificate

In order to use the new certificate, you must access the Proxmox dashboard from
the domain name that you generated the certificate for. To do that, you need to
edit your DNS.

You can edit your local DNS by adding the domain to `/etc/hosts`:

```
# snippet of /etc/hosts on the workstation:
# Enter the IP address of Proxmox VM :
X.X.X.X proxmox proxmox.example.com
```

```
# snippet of /etc/hosts on another LAN machine:
# Enter the LAN IP address of the workstation :
X.X.X.X proxmox proxmox.example.com
```

Or you may add this to the DNS server on DigitalOcean: 

 * Go to [cloud.digitalocean.com](https://cloud.digitalocean.com) and go to your
   project's `Networking` page in the main sidebar menu.
 * Click on `Domains`
 * Click on your domain name from the list.
 * Create a new type `A` record:
   * Enter the hostname: `proxmox.example.com` if `example.com` is the main
     domain.
   * Enter the *local LAN IP address* of the workstation. (this will not be
     routable outside your LAN, but DNS is cool with that.)
   * Click `Create Record`
   
Now you should be able to go to [https://proxmox.example.com:8006]() from
anywhere on your LAN (unless you added an IP filter in the firewall rule), and
you can access the Proxmox dashboard. Your web browser should now automatically
trust the certificate, issued by Let's Encrypt. Bookmark the dashboard, so that
you always access it using this full domain name.

## Exposing services to the Internet

After you have exposed the port to the LAN, you can configure your Internet
router to port forward certain port ranges to the workstation IP address, thus
exposing them to the Internet.

If you don't want to open your Internet router ports, you can use a VPN or do
something a bit fancier like [sish](https://github.com/antoniomika/sish) using
only SSH to tunnel traffic through another public bastion host.
