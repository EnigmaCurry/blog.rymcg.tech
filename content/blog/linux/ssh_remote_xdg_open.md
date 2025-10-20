---
title: "Make SSH remote xdg-open use your local web browser"
date: 2025-10-19T23:54:00-06:00
tags: ['linux', 'ssh']
---

Have you ever SSHed into a remote machine and ran a program that
wanted to automatically open a URL in your browser with `xdg-open`?

`xdg-open` is designed to open the URL in your preferred web browser.
On your local machine that usually works great. Logged in remotely,
over SSH, ithout a graphical session, it *may* try to open it in a
text mode browser (e.g., links, w3m), but more likely it will fail
altogether. Wouldn't it be cool if `xdg-open` running on the remote
machine could open URLs in your *local* web browser? Well, that's what
the following Bash script does.

## How it works

The following script works on Linux. It requires `bash`, `ssh`, and
`socat` to be installed on the local and all remote machines.

The script sets up a tiny reverse tunnel so that whenever the remote
machine runs `xdg-open https://example.org` the request is
transparently forwarded back to your local workstation, where your
normal browser handles it.

On the local side, a user-level systemd socket listens on
`~/.config/systemd/user/ssh_remote_xdg_open.socket`. Each connection
it receives will spawn a short-lived service that runs: `xargs -0 -n1
xdg-open`, to open each NUL-delimited URL it receives.

In your SSH host configurations (`~/.ssh/config`), you add the
following:

```
Host foo
    RemoteForward 127.0.0.1:19999 /run/user/1000/ssh_remote_xdg_open.sock
    ExitOnForwardFailure yes
```

When the remote host connects TCP to `127.0.0.1:19999`, SSH forwards
the data back into your local UNIX socket.

On the remote side, you need two helper programs (they will be
automatically installed via the script):

 * `~/.local/bin/open-local` – sends URLs through the tunnel.

 * `~/.local/bin/xdg-open` – a shim that uses the tunnel if available,
   otherwise falls back to the normal opener.

## Setup the script

On your local computer (the one where your graphical web browser
lives), download the script:

```
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_remote_xdg_open.sh
chmod +x ssh_remote_xdg_open.sh
```

Install the bundled systemd service on your local machine:

```
./ssh_remote_xdg_open.sh install-local
```

Configure your remote hosts in your local `${HOME}/.ssh/config`. Make
sure each remote has a given Host section:

```
## Basic host example in ~/.ssh/config
## This example assumes your user UID=1000

Host foo
    Hostname 192.168.1.1
    User root
    RemoteForward 127.0.0.1:19999 /run/user/1000/ssh_remote_xdg_open.sock
    ExitOnForwardFailure yes
```

You may run the script to automatically add the `RemoteForward` and
`ExitOnForwardFailure` fields to existing Host entries (e.g., `foo`):

```
./ssh_remote_xdg_open.sh configure-ssh foo
```

Install the helper script on the remote (e.g., `foo`):

```
./ssh_remote_xdg_open.sh install-remote foo
```

Test opening a URL from the remote (e.g., `foo`):

```
./ssh_remote_xdg_open.sh test foo
```

It should open the test URL in your local web browser and never let
you down.

Show the status of the socket / service:

```
./ssh_remote_xdg_open.sh status
```

To uninstall the socket/service, run:

```
./ssh_remote_xdg_open.sh uninstall-local
```

To remove the helper scripts onthe remote (e.g., `foo`):

```
./ssh_remote_xdg_open.sh remove-remote foo
```

## The script

 * [You can download the script from this direct
   link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/ssh/ssh_remote_xdg_open.sh)

{{< code file="/src/ssh/ssh_remote_xdg_open.sh" language="shell" >}}
