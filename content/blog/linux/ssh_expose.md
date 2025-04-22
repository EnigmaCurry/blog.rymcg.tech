---
title: "SSH Reverse Tunnel Manager"
date: 2025-04-21T23:54:00-06:00
tags: ['linux', 'ssh']
---

To gain remote access to a machine behind a NAT, you have quite a few
options. Some of the better ones include:

 1) Open a static port at the router.
 
 2) [Use a VPN](https://blog.rymcg.tech/blog/linux/wireguard_p2p/).

Both of these top options require some preplanning. Sometimes I want a
method that is considerably more temporary or ad-hoc, so heres another
option:

 3) Initiate a reverse tunnel to any old SSH host and expose a public
    port via the `GatewayPorts` option.

I like this third option for several reasons:

 * It doesn't require you to open any static ports on the NAT router
   (which you may not even have access to).
 * You probably already have some little VPS on the internet someplace
   that is running SSH.
 * No other software on the public host is required.
 * It's out of band of your primary VPN, so if you need to do remote
   maintaince on the VPN connection itself, you can still use this as
   a backdoor to get into your machines.

[Autossh](https://www.harding.motd.ca/autossh/) is a nice tool to
automatically maintain SSH tunnels, restarting them automatically if
they die. The following script sets up a systemd service that runs
`autossh` to maintain a reverse tunnel to your public SSH server and
expose a configured local port to the public internet.

## Dependencies

 * An SSH server running on some public VPS somewhere.
 * On the public VPS, install your local user's SSH pubkey in the
   `~root/.ssh/authorized_keys` file.
 * On your local machine, setup `~/.ssh/config` with an entry for the
   remote host:
   
```
# Example host in ~/.ssh/config

Host sentry
     Hostname sentry.example.com
     User root
     Port 22
```

 * On the public VPS, make sure that the port you wish to expose (e.g.
   `2222`) is not blocked by any firewall.

 * On your local machine, if you wish to create persistent tunnels
   that start on system boot, you must enable systemd lingering for
   your user account:
   
```
sudo loginctl enable-linger ${USER}
```

 * On your local machine, install `autossh` from your package manager.
 * On your local machine, download [the
   script](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_expose.sh):
 
```
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_expose.sh
chmod +x ssh_expose.sh
```

## Usage

All of the following commands are to be run from your local machine.

To setup the remote SSH config, use the script to enable
`GatewayPorts` and `AllowTcpForwarding` (this will automatically edit
the remote host's `/etc/ssh/sshd_config` file and restart the
service):

```
./ssh_expose.sh sshd-config sentry GatewayPorts=yes AllowTcpForwarding=yes
```

To create a temporary reverse tunnel from the VPS (`sentry`) port `2222` to `localhost:22`:

```
./ssh_expose.sh port sentry 2222 22
```

To make the tunnel survive a reboot, add `--persistent`:

```
./ssh_expose.sh port sentry 2222 22 --persistent
```

To close the tunnel (permanently):

```
./ssh_expose.sh port sentry 2222 22 --close
```

Or to close all tunnels (permanently):

```
./ssh_expose.sh port --close-all
```

List all active tunnels:

```
./ssh_expose.sh list
```

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_expose.sh)

{{< code file="/src/ssh/ssh_expose.sh" language="shell" >}}
