---
title: "Make SSH remote xdg-open use your local web browser"
date: 2025-10-19T13:54:00-06:00
tags: ['linux', 'ssh']
---

Have you ever SSHed into a remote machine and run a program that
tried to automatically open a URL in your web browser using `xdg-open`?

`xdg-open` is designed to open URLs in your preferred web browser. On
your local machine, that usually works great. Logged in remotely over
SSH, without a graphical session, it *may* try to open the URL in a
text-mode browser (e.g., `links`, `w3m`), but more than likely it will
fail to find any browser. Wouldn't it be cool if `xdg-open` running on
the remote machine could open URLs in your *local* web browser? That’s
exactly what the following Bash script does.

## How it works

The script works on Linux and requires `bash`, `ssh`, and
`socat` to be installed on both the local and remote machines.

It sets up a small reverse tunnel so that whenever the remote
machine runs `xdg-open https://example.org`, the request is
transparently forwarded back to your local workstation, where your
normal browser handles it.

On the local side, a user-level systemd socket listens on
`/run/user/${UID}/ssh_remote_xdg_open.sock`. Each connection it
receives spawns a short-lived service that runs `xargs -0 -n1
xdg-open` to open each NUL-delimited URL it receives.

In your SSH host configuration (`~/.ssh/config`), add the following:

```
## This example assumes your user UID=1000

Host foo
    RemoteForward 127.0.0.1:19999 /run/user/1000/ssh_remote_xdg_open.sock
    ExitOnForwardFailure yes
```

When the remote host connects via TCP to `127.0.0.1:19999`, SSH forwards
the data back into your local UNIX socket.

On the remote side, two helper programs are required (they’ll be
automatically installed by the script):

 * `~/.local/bin/open-local` – sends URLs through the tunnel.
 * `~/.local/bin/xdg-open` – a shim that uses the tunnel if available,
   otherwise falls back to the normal opener.

## Set up the script

On your local computer (the one with your graphical web browser),
download the script:

```
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_remote_xdg_open.sh
chmod +x ssh_remote_xdg_open.sh

```

Install the bundled systemd service locally:

```

./ssh_remote_xdg_open.sh install-local

```

Configure your remote hosts in your local `${HOME}/.ssh/config`.
Make sure each remote has a defined `Host` section:

```

## Basic host example in ~/.ssh/config

## This example assumes your user UID=1000

Host foo
    Hostname 192.168.1.1
    User root
    RemoteForward 127.0.0.1:19999 /run/user/1000/ssh_remote_xdg_open.sock
    ExitOnForwardFailure yes

```

You can also run the script to automatically add the `RemoteForward` and
`ExitOnForwardFailure` fields to an existing host entry (e.g., `foo`):

```

./ssh_remote_xdg_open.sh configure-ssh foo

```

Install the helper scripts on the remote host (e.g., `foo`):

```

./ssh_remote_xdg_open.sh install-remote foo

```

Test opening a URL from the remote host:

```

./ssh_remote_xdg_open.sh test foo

```

It should open the test URL in your local web browser — and never let
you down.

Check the status of the socket/service:

```

./ssh_remote_xdg_open.sh status

```

To uninstall the socket/service locally:

```

./ssh_remote_xdg_open.sh uninstall-local

```

To remove the helper scripts from the remote host:

```

./ssh_remote_xdg_open.sh remove-remote foo

```

## The script

 * [Download the script directly](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_remote_xdg_open.sh)

{{< code file="/src/ssh/ssh_remote_xdg_open.sh" language="shell" >}}
