---
title: "LAN-Only Internet Kill Switch"
date: 2026-02-19T12:00:00-06:00
tags: ['linux', 'networking']
---

When testing system deployments meant for air-gapped networks, you
need a way to simulate having no internet access while keeping LAN
connectivity intact. Rather than physically unplugging cables or
reconfiguring your router, this bash script gives you a quick toggle
to block all outbound internet traffic using `iptables`/`ip6tables`,
while preserving local network access.

This is useful for verifying that your deployment scripts, container
images, and service configurations actually work without reaching out
to the internet — catching missing dependencies, hardcoded external
URLs, or package manager calls that would fail in a real air-gapped
environment.

The script blocks all outbound traffic except:

 * **LAN traffic** — RFC 1918 IPv4 ranges (`10.0.0.0/8`,
   `172.16.0.0/12`, `192.168.0.0/16`) and IPv6 link-local / ULA
   ranges continue to work normally.
 * **DNS** — UDP and TCP port 53 to any destination, so name
   resolution keeps working.
 * **Explicit exceptions** — You can allowlist specific hostnames or
   IP addresses by editing the `EXCEPTIONS` array at the top of the
   script. You can optionally restrict exceptions to specific
   TCP/UDP ports.

It works with both `iptables-legacy` and `iptables-nft` (compat
layer), and handles both IPv4 and IPv6.

## How it works

The script creates a custom iptables chain (`LANONLY_OUT` /
`LANONLY6_OUT`) and inserts a jump to it at the top of the `OUTPUT`
chain. Inside that chain, it accepts DNS, LAN destinations, and any
configured exceptions, then drops everything else. Turning it off
simply removes the chain and its jump rule, restoring normal
connectivity.

## Installation

Download the script and make it executable:

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/network/internet-deny.sh
chmod +x internet-deny.sh
```

## Configuration

To allowlist specific hosts, edit the `EXCEPTIONS` array near the top
of the script:

```
EXCEPTIONS=(
  "example.com"
  "1.1.1.1"
  "2606:4700:4700::1111"
)
```

Hostnames are resolved at enable time. To restrict exception hosts to
specific ports:

```
EXCEPTION_TCP_PORTS=(
  443 22
)
EXCEPTION_UDP_PORTS=(
  123
)
```

If the port arrays are left empty, all ports are allowed to exception
destinations.

## Usage

The script requires root privileges and will automatically invoke
`sudo` if needed:

```
## Enable LAN-only mode (block internet):
./internet-deny.sh on

## Disable LAN-only mode (restore internet):
./internet-deny.sh off

## Check current status:
./internet-deny.sh status
```

## Notes

 * The rules are **not persistent** across reboots — if you reboot,
   internet access is restored. Run `./internet-deny.sh on` again
   after boot if you want to re-enable it.
 * DNS is always allowed so that hostname resolution works. If you
   need to block DNS too, you'll need to modify the script.
 * Exception hostnames are resolved to IP addresses once at enable
   time. If the DNS records change, you'll need to cycle
   `off` / `on` to pick up the new addresses.

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/network/internet-deny.sh)

{{< code file="/src/network/internet-deny.sh" language="shell" >}}
