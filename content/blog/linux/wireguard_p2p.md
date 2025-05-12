---
title: "WireGuard P2P VPN"
date: 2025-04-20T23:39:00-06:00
tags: ['linux', 'wireguard']
---

[WireGuard](https://www.wireguard.com/) is a super fast and simple VPN
that makes it easy to set up secure, ad-hoc, private connections using
the latest encryption tech. WireGuard's design makes no distinction
between "server" and "client" — every node is simply a peer. You could
_designate_ a particular node as a "server", and build a hub-and-spoke
architecture, or you can design a full mesh network where every node
can talk to every other node. This post will focus on the latter.

The following Bash script sets up a p2p VPN between two or more Linux
(systemd) machines. The only network requirement is that each host has
the ability to make _outbound_ UDP connections ([Full Cone or
Restricted Cone
NAT](https://en.wikipedia.org/wiki/UDP_hole_punching)). For most
residential ISP connections, this will work out of the box. If your
connection uses Symmetric NAT or CGNAT (typical in corporate, hotel,
and mobile networks) this might not work so well.

The magic of this setup is that it works without needing to make any
modifications to your home router, you don't need to open any static
ports, and you don't need to pay for an external VPN server or
provider!

Note: this script will create VPN routes *only* between the hosts that
you specify. It will not modify your normal Internet connection to any
other hosts.

## Example

Lets say you have three Linux hosts, with the following hostnames and
public IP addresses, all on different networks:

 * `defiant` - 45.67.89.10
 * `enterprise` - 156.123.98.34
 * `voyager` - 23.47.88.14

If your hosts don't have static IP addresses, you might want to set up
dynamic DNS and use fully qualified domain names instead. For this
example, we'll just use the public IP addresses (most residential IP
addresses tend to stay the same for long periods).

You must download [the
script](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/wireguard/wireguard_p2p.sh)
onto each Linux host you want to join the VPN. The script will handle
installing WireGuard if it's not already installed (if your OS is
unsupported, try [installing WireGuard
manually](https://www.wireguard.com/install/) first).

On `defiant`, run:

```
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/wireguard/wireguard_p2p.sh
chmod +x wireguard_p2p.sh

./wireguard_p2p.sh install 10.15.0.1/24
```

This will give `defiant` the VPN address of `10.15.0.1`.

It will print out the `add-peer` command you need to run on the other
hosts, which includes the public endpoint and key for `defiant`:

```
------------------------------------------------------------
To add THIS node as a peer on another WireGuard server using this script, run:

./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI= 10.15.0.1

(Replace 'defiant' with your desired label for this peer.)
------------------------------------------------------------
```

Notes:

 * If you need to print the `add-peer` information again, run
   `./wireguard_p2p.sh add-peer` with no other arguments.

 * If you don't have public static IP addresses, simply replace the IP
   address with the domain name (FQDN). Keep the `:51820` port the
   same. (e.g. `host.example.com:51820`)

Don't run the `add-peer` command on the other hosts yet. You must
install the script on `enterprise` and `voyager` the same way as you
did on `defiant`, except with different (sequential) VPN addresses:

 * On `enterprise`: `./wireguard_p2p.sh install 10.15.0.2/24`
 * On `voyager`: `./wireguard_p2p.sh install 10.15.0.3/24`

These commands will print out a similar `add-peer` command with their
own endpoint and key. Gather all three `add-peer` commands,
and then run them on each other host:

(Note: all of the IP addresses and public keys listed here are
_examples_ for demonstration purposes. You should use the real
`add-peer` command for your actual hosts instead!)

On `defiant`: add `enterprise` and `voyager`:

```
./wireguard_p2p.sh add-peer enterprise 156.123.98.34:51820 Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk= 10.15.0.2
./wireguard_p2p.sh add-peer voyager 23.47.88.14:51820 xpW2S5aJaEj2JSbmRdUMBt12y1lhz003m5WKi70YOj4= 10.15.0.3
```

On `enterprise`: add `defiant` and `voyager`:

```
./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI= 10.15.0.1
./wireguard_p2p.sh add-peer voyager 23.47.88.14:51820 xpW2S5aJaEj2JSbmRdUMBt12y1lhz003m5WKi70YOj4= 10.15.0.3
```

On `voyager`: add `defiant` and `enterprise`:

```
./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI= 10.15.0.1
./wireguard_p2p.sh add-peer enterprise 156.123.98.34:51820 Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk= 10.15.0.2
```

Now that all three hosts have been installed, and have added each
other peer in full mesh, the VPN should be up and fully functional!

Check the status on each peer. Just run `wg`. For example, on
`defiant`, it will list two peers:

```
root@defiant:~# wg
interface: wg0
  public key: du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI=
  private key: (hidden)
  listening port: 51820

peer: xpW2S5aJaEj2JSbmRdUMBt12y1lhz003m5WKi70YOj4=
  endpoint: 23.47.88.14:51820
  allowed ips: 10.15.0.3/32
  latest handshake: 16 seconds ago
  transfer: 92 B received, 180 B sent
  persistent keepalive: every 25 seconds

peer: Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk=
  endpoint: 156.123.98.34:51820
  allowed ips: 10.15.0.2/32
  latest handshake: 16 seconds ago
  transfer: 124 B received, 180 B sent
  persistent keepalive: every 25 seconds
```

This shows that both of the other peers (`enterprise` and `voyager`)
are added. Unfortunately, it won't show their hostnames, but it does
show their public keys.

The *most important* thing to look for is: `latest handshake: X
seconds ago`. If you don't see `latest handshake`, or if it shows a
time greater than 25 seconds, then something is wrong, and preventing
p2p connection between the machines.

If all three machines show a good handshake, you should now be able to
ping each other host, e.g. on `defiant`:

```
ping -c1 10.15.0.2
ping -c1 10.15.0.3
```

Now you know how to setup a peer-to-peer VPN, between any number of
hosts, all without needing to pay for any third party service!

## Usage

```
Usage: ./wireguard_p2p.sh <command>

Commands:
  dependencies                       Install required packages.
  install <address-cidr>             Install and configure WireGuard. Required first time.
  uninstall                          Remove WireGuard configuration and keys.
  status                             Show the WireGuard service status.
  start                              Start the WireGuard service.
  stop                               Stop the WireGuard service.
  import-key PRIVATE_KEY             Import a private key instead of generating one.
  add-peer NAME ENDPOINT PUBLIC_KEY  Add peer live and auto-save into config.
  remove-peer PUBLIC_KEY             Remove peer live and auto-save into config.
  help                               Show this help message.

```

## Outbound NAT issues

Even if you have verified that your ISP has given you a public, static
IP address, with full Internet connectivity, you might still find that
your router prevents this scenario from working as described.


### pfSense

Here is one example with a pfSense router. 

pfSense has four possible [Outbound NAT
settings](https://docs.netgate.com/pfsense/en/latest/nat/outbound.html),
(but you only need to be concerned with the first two):

 * `Automatic Outbound NAT` - this is the default setting, and is most
   useful for home Internet services. This will allow high levels of
   TCP and UDP traffic, from many clients, without interference. All
   outbound connections will be assigned a temporary random source
   port mapping between the LAN client and the WAN interface. The
   router will use this unique port mapping to create the
   bi-directional route between your client and destination for the
   duration of the call.
   
   This setting cannot be used with the WireGuard scenario we've
   described so far. This is because the _outbound source_ UDP port
   must be static.
   
 * `Hybrid Outbound NAT` - this setting is just like `Automatic
   Outbound NAT`, except that it also lets you create exceptional
   rules for certain traffic routes. This lets you use the automatic
   mode for most traffic (random source ports), but will also set up a
   specific rule to let WireGuard use a _static_ source port from a
   specific host.

To create a custom rule for WireGuard traffic, make sure to select
`Hybrid Outbound NAT`.

Create a [Host
   Alias](https://docs.netgate.com/pfsense/en/latest/firewall/aliases-types.html#host-aliases)
   for both peers:

 * For the local WireGuard peer, enter the private LAN IP address.
   
 * For the destination peer, enter the public FQDN or IP address.

Create the [Static
   Port](https://docs.netgate.com/pfsense/en/latest/nat/outbound.html#static-port)
   outbound NAT rule.
   
  * Interface: `WAN`
  * Address Family: `IPv4+IPv6`
  * Protocol: `UDP`
  * Source: Choose `Network or Alias` and select the LAN host alias
     (`{host}/32`) and choose the _source_ port that WireGuard is
     listening to.
  * Destination: Choose `Network or Alias` and select the WAN host
     alias of your remote peer (`{remote}/32`) and choose the
     _destination_ port that WireGuard peer is listening to.
     
With this rule active, the source port on the receiving end will now
always match the WireGuard listening port.

### Troubleshooting NAT

You can verify the UDP source ports using `tcpdump`:

```
tcpdump -n -i any udp
```
     
The output of `tcpdump` shows packets both being sent and received,
with the source and destintations hosts and ports. To deduce whether
NAT is being (mis)applied, you must run this on both peers to get
their own perspective. Critically, for this scenario to work, both the
sender and receiver must see the same _source_ ports. Whereas the IP
address will be translated public<->private, the ports are static.

## Provisioning new peers

WireGuard supports many platforms beyond just Linux. However, this
Bash script is only designed for Linux. No problem though, because you
can use this script to create keys and config files using the standard
WireGuard `.conf` file format, which is supported on Windows, macOS,
Linux, Android, and iOS.

For the most secure VPN, you should have each peer generate their own
key. In the context of this script, "provisioning" a peer means that
we are taking a shortcut, and generating a key on behalf of that peer
and providing it to them ahead of time, embedded it into a `.conf`
file. This is more convenient to hand your to your trusted friend,
rather then to have to exchange keys. It also means we don't have to
port the script to any other platforms, because all the keys will be
provisioned from the Linux host.

Running the `provision-peer` subcommand, on the Linux host, will:

 * Generate a fresh keypair for the other peer.

 * Emit a ready-to-import `.conf` file (complete with private key, VPN
   address, and this peers public key and endpoint).

 * Print the exact `add-peer` command to run on the Linux host to add
   the new peer connection.


### Example of provisioning

For example, your friend has a Windows computer (or mac, android, ios,
etc.):

 * `borg` - 34.56.78.90

Generate a new key and config on their behalf:

```
./wireguard_p2p.sh provision-peer borg 34.56.78.90:51820 10.15.0.4/24
```

 * Make sure to enter borg's public IP address (e.g. 34.56.78.90) -
    Your friend should double check via [ifconfig.me](ifconfig.me).
 * The endpoint port 51820 can be customized for their machine. You
   may need to experiment with different ports especially if its
   already being used for something else on their end.
 * Enter an unused private IP address/CIDR for use on the VPN subnet.

Copy the `add-peer` command that the `provision-peer` outputs and run
it:

```
./wireguard_p2p.sh add-peer borg x.x.x.x:51820 o7iXZVberLzQclBG+9U4+BJozKVhOl3Mqgaj9MCLST8=  10.15.0.4/24
```

Grab the peer's config:

```
cat /etc/wireguard/provisioned_peers/borg.conf
```

 * Copy the config output and give it to your friend in an email or
   chat message.

 * Your friend needs to [download
   WireGuard](https://www.wireguard.com/install/) and install it.

 * They should save the config text into a file named `[peer].conf`
   (they should replace [peer] with the name of *your* peer).
   
 * The config file can be imported via the WireGuard GUI. Once
   imported, it should immediately connect.
   
 * Tell your friend to look for the `handshake`, or how to ping your
   peer's VPN address to check that everything is working.

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/wireguard/wireguard_p2p.sh)

{{< code file="/src/wireguard/wireguard_p2p.sh" language="shell" >}}
