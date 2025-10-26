---
title: "WebDAV with Rclone"
date: 2025-10-26T13:54:00-06:00
tags: ['linux', 'rclone', 'webdav']
---

[WebDAV](https://datatracker.ietf.org/doc/html/rfc4918) is an open
extension to HTTP that lets you treat a web server like a remote
filesystem. [Rclone](https://rclone.org/) is an open source WebDAV
client that lets you mount remote volumes for read/write access on
your local computer.

## Provision your WebDAV server

You can use whatever WebDAV server you have access to. If you need to
install one, I recommend
[copyparty](https://github.com/9001/copyparty) or
[nextcloud](https://nextcloud.com/) (Use the
[d.rymcg.tech](https://github.com/enigmaCurry/d.rymcg.tech?tab=readme-ov-file#readme)
distribution to install these on Docker.)

## Mutual TLS (optional)

For extra security, the server may require authentication with a
client TLS certificate, which this script fully supports. You will
just need to place the certificate file (e.g., `ryan-files.pem`) and
the unencrypted key file (e.g., `ryan-files.key`) and put them
someplace permanent (e.g., directly in the rclone config directory).

```bash
## Copy the cert and key file to someplace permanent:
mkdir -p ~/.config/rclone
cp ryan-files.pem ~/.config/rclone/
cp ryan-files.key ~/.config/rclone/
```

Note: the certificate should have been provided to you by your
administrator. If you are deploying your own server, check out
[Step-CA](https://smallstep.com/docs/step-ca/) (and the
[d.rymcg.tech](https://github.com/EnigmaCurry/d.rymcg.tech)
distribution for installing it on Docker).

## Example

For the examples in this post, we'll assume the following connection
details for your WebDAV service:

 * URL: `https://files.example.com` 
   * Note: for copyparty, there is usually no path necessary. For
     Nextcloud, you need to specifiy the URL with a path, e.g.:
     `https://files.example.com/nextcloud/remote.php/dav/files/USERNAME/`)

 * Username: `ryan`
   * HTTP authentication username.
   * Note: copyparty ignores the username field.
   
 * Password: `hunter2`
   * HTTP authentication password.
   * Note: for copyparty, this is your only authentication (besides mTLS).
   
 * Volume name: `ryan-files`
   * This is the internal name that Rclone will reference this remote with.
   * This is also the default name of the mount point. (e.g.,
     `~/ryan-files`)
     
 * Certificate: `~/.config/rclone/ryan-files.pem`
   * Optional
   
 * Key: `~/.config/rclone/ryan-files.key`
   * Optional

## Download the script

```bash
wget https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/rclone/rclone_webdav.sh
chmod +x rclone_webdav.sh
```

## Configuration

Create a new config (or updates an existing one) named `ryan-files`:

```bash
./rclone_webdav.sh config ryan-files
```

Follow the prompts to configure the volume:

```
== Interactive rclone WebDAV setup (idempotent) ==
Remote volume name (e.g., ryan-files): ryan-files
WebDAV URL (e.g., https://copyparty.example.com): https://files.example.com
Vendor (copyparty|owncloud|nextcloud|other) [copyparty]: copyparty
Username (HTTP Auth; username ignored copyparty): admin
Password (HTTP Auth): hunter2
Client certificate PEM path [/var/home/ryan/.config/rclone/client.crt]: /var/home/ryan/.config/rclone/ryan-files.pem
Client key PEM path [/var/home/ryan/.config/rclone/client.key]: /var/home/ryan/.config/rclone/ryan-files.key
Mount point (absolute) [/var/home/ryan/ryan-files]: /var/home/ryan/ryan-files
```

This will save the Rclone configuration to
`~/.config/rclone/rclone.conf`.

## Install service

Install the systemd/User service to automatically mount the volume:

```bash
./rclone_webdav.sh enable ryan-files
```

Now the remote volume should be mounted locally at `~/ryan-files` and
will automatically mount when your system boots or when you login.

## Check service status

```bash
./rclone_webdav.sh status ryan-files
```

## Check logs for debugging purposes

```bash
./rclone_webdav.sh log ryan-files
```

## Uninstall service

```bash
./rclone_webdav.sh uninstall ryan-files
```

## The script

 * [Download the script directly](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/rclone/rclone_webdav.sh)

{{< code file="/src/rclone/rclone_webdav.sh" language="shell" >}}
