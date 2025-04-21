---
title: "WireGuard P2P"
date: 2025-04-20T23:39:00-06:00
tags: ['linux', 'wireguard']
---

[WireGuard](https://www.wireguard.com/) is a super fast and simple VPN
that makes it easy to set up secure, private connections using the
latest encryption tech. WireGuard has no server, clients talk to
eachother in a peer-to-peer fashion. 

The following script sets up a direct p2p connection between two or
more Linux machines. The only requirement is that each host has the
ability to make _outbound_ UDP connections (Full Cone NAT). For most
residential ISPs, this will work out of the box. If you are using a
corporate network (business, hotel, etc.) this might not work as well.

## Usage

For example, lets say you have the following Linux hosts, with the
_example_ public IP addresses, all on different networks:

 * `defiant` - 45.67.89.10
 * `enterprise` - 156.123.45.67
 * `voyager` - 23.45.67.89
 
You must download [the
script](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/wireguard/wireguard_p2p.sh)
onto each Linux host you want to join the VPN, and make it exectable. The script will handle
installing wireguard if its not already installed.

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

./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI=

(Replace 'defiant' with your desired label for this peer.)
------------------------------------------------------------
```

But before you do that though, you must install the script on
`enterprise` and `voyager` the same way as you did on `defiant`,
except with different (sequential) VPN addresses:

 * On `enterprise`: `./wireguard_p2p.sh install 10.15.0.2/24`
 * On `voyager`: `./wireguard_p2p.sh install 10.15.0.3/24`

These commands will similarly print out `add-peer` commands. Now you
need to run all of the `add-peer` commands on each other host.

(Note: all of the IP addresses and public keys are _examples_ for
demonstration purposes. You should copy and paste the exact `add-peer`
command the `install` command provides instead!)

On `defiant`, add `enterprise` and `voyager`:

```
./wireguard_p2p.sh add-peer enterprise 156.123.45.67:51820 Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk=
./wireguard_p2p.sh add-peer voyager 23.45.67.89:51820 xpW2S5aJaEj2JSbmRdUMBt12y1lhz003m5WKi70YOj4=
```

On `enterprise`, add `defiant` and `voyager`:

```
./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI=
./wireguard_p2p.sh add-peer voyager 23.45.67.89:51820 xpW2S5aJaEj2JSbmRdUMBt12y1lhz003m5WKi70YOj4=
```

On `voyager`, add `defiant` and `enterprise`:

```
./wireguard_p2p.sh add-peer defiant 45.67.89.10:51820 du6ODGzyU742OIOMNjB3lu5nzUR4zxLnsrTuIrb1ZhI=
./wireguard_p2p.sh add-peer enterprise 156.123.45.67:51820 Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk=
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
  endpoint: 23.45.67.89:51820
  allowed ips: (none)
  latest handshake: 16 seconds ago
  transfer: 92 B received, 180 B sent
  persistent keepalive: every 25 seconds

peer: Tx+JOAaZmGZCsE8qqy5AYFnXI7zksC4C2GOjfRlb8lk=
  endpoint: 156.123.45.67:51820
  allowed ips: 10.15.0.0/24
  latest handshake: 16 seconds ago
  transfer: 124 B received, 180 B sent
  persistent keepalive: every 25 seconds
```

This shows that both of the other peers (`enterprise` and `voyager`)
are added. It doesn't show their hostnames, but it shows the public
keys.

The *most important* thing to look for is: `latest handshake: X
seconds ago`, and X must always be less than 25 seconds. If it doesn't
say that, or if its greater than 25 seconds, something is wrong, and
preventing p2p connection between the machines.

You should now be able to ping each other host, e.g. on `defiant`:

```
ping 10.15.0.2
ping 10.15.0.3
```

Now you know how to setup a peer-to-peer VPN, between any number of
hosts, all without needing to pay for any third party service!

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/wireguard/wireguard_p2p.sh)

{{< code file="/src/wireguard/wireguard_p2p.sh" language="shell" >}}
