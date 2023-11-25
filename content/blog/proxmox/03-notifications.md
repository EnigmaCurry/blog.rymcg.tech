---
title: "Proxmox part 3: Notifications"
date: 2022-05-04T00:02:00-06:00
tags: ['proxmox']
---

Now that you have installed Proxmox, created a storage pool, and
configured the networking, you'll want to setup notifications in case
a hardware error occurs, or in the case of a backup job failing. Let's
setup email notifications, and test that they are working.

Prior to Proxmox 8.1, to do this you had to configure postfix by hand,
and setup your outgoing SMTP server and credentials. If you upgrade to
Proxmox 8.1, this is now much nicer: there is a new dashboard menu to
setup the authenticated SMTP relay.

# Requirements

 * A Proxmox server ([start with step 1](/blog/proxmox/01-install/) if
   you haven't already)
 * An external SMTP relay service

Sending email in 2023 is near impossible unless you use a provider
that makes it their full time job to ensure that their servers are not
blacklisted nor sent to spam. Its not feasable to reliably self-host
your own general outgoing SMTP relay, you're going to need to use a
third party email account/service for that. (On the other hand, you
could self-host an entire [email server](https://mailu.io/), and as
long as both the sending account and the recipient account are on the
same host, then this is not a problem.)

For security purposes, and by following the rule of least privilege, I
recommend that you use a kind of SMTP service that is designed for
sending only (eg. mailgun). You should not use the same SMTP account
credentials as you use for your personal mail. You should use an
email/smtp account that is dedicated to the Proxmox user, and should
not have any other purpose.

# Upgrade to at least Proxmox 8.1

 * Click on your pve host under the `Datacenter` list.
 * Click `Updates`
 * Click `Upgrade`
 * This will open a shell and do any pending upgrades
 * Reboot if prompted to do so
 * Verify the version is now 8.1+, printed in the top left of the
   dashboard

# Verify the root user's email address setting

 * Click `Datacenter`
 * Under `Permissions`, click `Users`
 * Click the `root` user
 * Click `Edit`
 * Verify the `E-Mail` address is correct. You should put your own
   email address here, so that you receive all the mail that the root
   Proxmox user should receive

# Configure a new SMTP notification target

 * Click `Datacenter`
 * Click `Notifications`
 * Under `Notification targets`, click `Add`, then choose `SMTP`
 * Fill in all the details of your external SMTP account:
  * Enmter the endpoint name, like: `My external SMTP relay`
  * Enter your provider's SMTP `Server` domain name: `mail.example.com`
  * Choose the `Encryption` (usually `TLS`, check with your provider)
  * Enter the `Port` number (usually 465 or 587, check with your provider)
  * Enter the `Username` and `Password` for your provided SMTP account.
  * Enter the `From` Address, this can usually be whatever you like,
    eg. `root@pve`
  * Select the `Recipient(s)` - choose `root@pam` - unless you use a
    different Proxmox account than root, choose `root@pam`
  * You should not need to fill in the `Additional Recipient(s)`
    unless you want to
  * Click `Add`

## Test the new SMTP notification target

 * Click on the new notification target in the list
 * Click the `Test` button
 * Click `Yes`, to confirm that you would like to send the test email
 * Verify that you do recieve the test email

## Disable the builtin `mail-to-root` notification target

You should now see two `Notifications Targets` listed: 1) mail-to-root
and 2) your external SMTP server. You should disable the first one,
`mail-to-root`, as the new one will serve that role instead:

 * Click the `mail-to-root` entry
 * Click `Modify`
 * Uncheck the `Enable` flag
 * Click `OK`
 * Verify the builtin `mail-to-root` is now disabled (shows an icon
   like `—` instead of `✔`). (You can't remove it, because its
   builtin, you can only disable it.)

# Configure the default notification matcher

You want *all* notifications to go to the root user, via your new SMTP
notification target, so you need to edit the `default-matcher`
notification target:

 * Click the `default-matcher` notification target
 * Click `Modify`
 * Click `Targets to notify`
 * Uncheck `mail-to-root`
 * Check the new SMTP target
 * Click `OK`

# Configure Gotify (optional)

As an alternative to Email, or in addition to, you can send
notifications via [Gotify](https://gotify.net/) which supports [an
android app](https://f-droid.org/de/packages/com.github.gotify/) to
receive mobile push notitfications. The advantage here is that a
gotify server is much easier to setup than an email server, and you
don't have to worry about messages going to spam.

I am not too interested in having yet another app on my phone
maintaining a connection 24/7, just to receive the occasional
emergency notification. So I would want to receive the notification in
Matrix (Element), so I have my eye on
[Ondolin/gotify-matrix-bot](https://github.com/Ondolin/gotify-matrix-bot)
but I have not tested it yet.

I feel like it was a missed opportunity for Proxmox to support gotify,
but not [ntfy](https://ntfy.sh/) which better handles the multiple
connection problem, on android at least.
