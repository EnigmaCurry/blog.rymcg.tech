---
title: "Proxmox part 8: TrueNAS Core"
date: 2023-11-18T00:02:00-06:00
tags: ['proxmox']
---

Networked Attached Storage (NAS) is a very useful service to provide
for your homelab. It can serve many different roles:

 * Samba share on your LAN for storing all your files
 * NFS remote for mounting as proxmox VM storage
 * local S3 compatible buckets
 * iSCSI block storage
 * and more

Proxmox has great ZFS support all by itself, and if you only need to
create VMs, you should probably stick with that. If you want to create
a Samba share, or do any of the other things listed above, Proxmox
can't do things alone.

[TrueNAS Core](https://www.truenas.com/) is a FreeBSD distribution
that is custom built to serve the role of a NAS appliance and can do
all the things listed above. By creating a a TrueNAS VM on Proxmox,
you can dedicate all of your storage devices (except the proxmox boot
device) to the TrueNAS VM, and then re-mount those disks back on
Proxmox over NFS, available to use as a storage pool for other VMs on
proxmox.

You might call this an Ouroboros situation.

{{<img src="/img/Serpiente_alquimica.jpg" alt="The uroboros serpent, eating its own tail">}}

## Upload the TrueNAS Core .iso image

 * [Download the TrueNAS core .iso image
   here](https://www.truenas.com/download-truenas-core/)
 * Open your proxmox dashboard
 * Underneath the proxmox host found in `Datacenter` list, click on
   the `local` storage pool.
 * Click `ISO Images`
 * Click `Upload` and select the .iso image to upload (`TrueNAS-13.0-U5.3.iso` or similar)

## Create the TrueNAS VM

For demonstration purposes, this configuration will use three virtual
disk images: 1) for the boot device, with 2) and 3) for a ZFS mirrored
data pool for initial testing purposes only. (You will add your own
physical disks and create a final pool later on):

 * Under the `Datacenter` list, right click the proxmox server
 * Click `Create VM`
 * Enter the name: `truenas`
 * Select the ISO image you uploaded
 * Choose the storage pool for the root disk.
 * Leave the default size of 32GB (it won't need very much of that).
 * Click `Add` to add an additional disk, 32GB or whatever.
 * Click `Add` and create a *third* disk, same size as before.
 * Give it some CPU cores (2) and some RAM (8192)
 * Finalize the creation of the VM.

## Add serial numbers to the virtual drives

TrueNAS requires each drive in your storage pools to have a unique
serial number. By default, Proxmox does not assign any serial numbers
to the virtual disks, and there also does not appear to be any way to
add a serial using the dashboard. You must edit the VM configuration
file by hand:

 * Login to the Proxmox console, either by SSH, or through the `Console` tab.
 * Use a text editor (`nano`) to edit the VM configuration file:
   `/etc/pve/nodes/{host}/qemu-server/{vm_id}.conf`
 * Find the line that starts with `scsi0`, add append the following text: `,serial=0000`
 * Find the line that starts with `scsi1`, add append the following text: `,serial=0001`
 * Find the line that starts with `scsi2`, add append the following text: `,serial=0002`
 * In the dashboard navigate to the VM's `Hardware` page and verify the serials have been added.

## Install TrueNAS Core

 * Click on the new VM ID (truenas) in the server list.
 * Click `Console`
 * Click `Start now`
 * The TrueNAS installer will boot.
 * Choose `Install/Upgrade` and press Enter.
 * Select only the first hard drive in the list to use as the root
   device.
 * Proceed with the installation.
 * Choose a root password.
 * Select `Boot via BIOS`.
 * When the installation is complete, reboot the VM.
 * The VM will restart and print a lot of `...+..` to the screen for
   awhile.
 * You should now see the `Console setup` menu.
 * Notice the URL printed to the console, containing the IP address of
   the truenas VM.

## Configure TrueNAS Core

 * Open the VM URL in your browser.
 * Login as the `root` user using the password you created during
   install.

### Configure the root user account

 * Click `Accounts`
 * Click `Users`
 * Find the `root` user and click the blue arrow on the right.
 * Click `Edit`
 * In the `Email` field, enter your own email address
 * In the `SSH Public Key` field, enter your own SSH public key (eg.
   from your workstation's ssh agent `ssh-add -L`, or from
   `~/.ssh/id_rsa.pub`)
 * Click `Save`

### Configure user accounts

You should limit the `root` account only to administrative tasks, for
daily usage, you should use a user account instead:

 * Click `Accounts`
 * Click `Users`
 * Click `Add`
 * Enter the name, username, email address, password. (Do not enter
   any SSH key, as the user will have no home directory)
 * Click `Submit`

### Configure the timezone

 * Click `System`
 * Click `General`
 * Select your server's timezone
 * Click `Save`

### Configure Email SMTP server

Email notifications are optional, but highly recommended so that you
can quickly become aware of any critical storage errors that may
arise. To send mail from TrueNAS, you will need access to an external
outgoing SMTP server (TODO: a future post will show how to install
postfix on your Proxmox host, and how to create a private network
between truenas and proxmox, to help protect access to your SMTP
server).

 * Click `System`
 * Click `Email`
 * Enter the `Outgoing Mail Server` address
 * Verify the corrent port, TLS setting, and authentication settings (if applicable)
 * Send a test mail to ensure mail is functional. It will send it to
   the email address you set for the `root` user.
 * Click `Save`

You can configure all the different types of alerts under `Alert
Settings`.

### Create a storage pool

The initial pool will just be for demo purposees, using the two extra
virtual disks added to the VM at creation:

 * Click `Storage`
 * Click `Pools`
 * Click `Add`
 * Click `Create Pool`
 * Enter a name: `test`
 * Select the two disks from the `Available Disks` column: `da1` and
   `da2`
 * Click the blue right pointing arrow to add them to the `Data VDevs`
   column.
 * The default `Mirror` strategy is preselected.
 * Click `Create` and confirm.

## Create an SMB file share

### Create the Movies dataset

For this example, we will create a dataset sharing some movie files:

 * Click `Storage`
 * Click `Pools`
 * Find the `test` pool you created
 * Click the three dot context menu on the right
 * Click `Add Dataset`
 * Enter the name: `Movies`
 * Click `Submit`
 * Find the new `Movies` dataset, and click the three dot context menu
   on its right hand side.
 * Click `Edit permissions`
 * Select the `User` using the username you created (not root).
 * Click `Apply User`
 * Select the `Group` using the same username (not wheel).
 * Click `Apply Group`
 * Click `Save`

### Create the Movies share

To share our Movies dataset with other devices on the LAN, a Samba
share may be created:

 * Click `Sharing`
 * Click `Windows Shares (SMB)`
 * Click `Add`
 * Find the folder under `/mnt/test/Movies` and select `Movies`
 * Leave the name as the same: `Movies`
 * Click `Advanced Options`
 * Enable `Allow Guest Access`
 * Click `Submit`
 * If you have not yet enabled the SMB service, it will ask to: click
   `Enable Service`
 * It should ask you to configure the ACL: click `Configure Now`
 * Choose `Select a preset ACL` and select the `OPEN` preset.
 * Click `Continue`
 * Scroll down in the `Edit ACL` dialog that remains open, there are
   three sections: 1) owner 2) group 3) everyone.
 * Near the bottom find the `everyone` config and change the
   `Permissions` to `Read`.
 * Click `Save`


### Test the Samba share from another desktop

Use your file browser to browse the network, you should find the
truenas SMB service and the `Movies` folder inside. You should be
presented with an authentication dialog and you can choose to login
anonymously, or with the truenas username/password for the user
account you created. The anonymous user should only be able to read
files, not create nor delete anything. Only the authenticated user
account may modify the files.

## Create an NFS share for proxmox use

This is where the Ouroborus makes his move, you can create an NFS
share so that the Proxmox host may mount the storage provided by
TrueNAS, so that *other* VMs on the same host may use the storage
provided.

### Create a private network for NFS between proxmox and truenas

Create the private bridge:

 * On the proxmox host dashboard, click on the server in the
   `Datacenter` list
 * Click `Network`
 * Click `Create`
 * Click `Linux Bridge`
 * Enter the name: `vmbr50`
 * Enter the IPv4/CIDR: `10.50.0.1/24`
 * Enter the description: `Local TrueNAS access only`
 * Click `Create`
 * Click `Apply Configuration`

Create the private network link:

 * Find the truenas VM in the list, and go to its `Hardware` page.
 * Click `Add`
 * Click `Network Device`
 * Choose the bridge: `vmbr50 (Local TrueNAS access only)`
 * Click `Add`
 * Reboot the truenas VM so that it detects this new network device.

Once the trunas VM has rebooted, open the truenas dashboard:

 * Click `Network`
 * Click `Interfaces`
 * Find the second interface `vtnet1` and click the blue arrow on the
   right hand side.
 * Click the `EDIT` button (scroll down, it may be hidden)
 * Unselect `DHCP`
 * Enter the IP address: `10.50.0.2`
 * Click `Apply`
 * Make sure the first interface `vtnet0` retains the DHCP setting
   (yes). (it may need to be turned back on after disabling dhcp on
   the other interface, weird.)
 * Click `Test Changes` and confirm
 * Click `Save Changes`

### Create the PVE dataset

 * Click `Storage`
 * Click `Pools`
 * Find the `test` pool you created
 * Click the three dot context menu on the right
 * Click `Add Dataset`
 * Enter the name: `PVE`
 * Click `Submit`

### Create the PVE share

 * Click `Sharing`
 * Click `Unix Shares (NFS)`
 * Click `Add`
 * Find the folder under `/mnt/test/PVE` and select `PVE`
 * Leave the name as the same: `PVE`
 * Click `Advanced Options`
 * Select the `Maproot User`: `root`
 * Select the `Maproot Group` `wheel`
 * Enter the Authorized Hosts and IP addresses: `10.50.0.1`
 * Click `Submit`
 * If you have not yet enabled the NFS service, it will ask to: click
   `Enable Service`

### Mount the NFS share on Proxmox

 * On the proxmox dashboard, click the `Datacenter` at the top of the list
 * Click `Storage`
 * Click `Add`
 * Click `NFS`
 * Enter the ID: `truenas`
 * Enter the server IP address: `10.50.0.2`
 * Enter the export: `/mnt/test/PVE`
 * Choose all the Content types you want to store on this share,
   probably just: `Disk Image` and `Container`
 * Click `Add`

Now you have a new storage pool on proxmox, hosted by the nested
truenas VM, with which to store VM disks!

## Configure the truenas VM to start before all others

If you have just now setup the NFS storage, the truenas VM is now part
of your critical infrastructure. You need to ensure that the truenas
VM starts on boot *before* all other VMs that require the storage
provided by it.

 * On the proxmox dashboard, click on the truenas VM
 * Click `Options`
 * Double click the `Start at boot` field
 * Checkmark the `Start at boot` box
 * Click `OK`
 * Double click the `Start/Shutdown order` field
 * Enter the star/shutdown order: `1`
 * Enter the startup delay: 150 (this is the time that delays all
   *other* VMs. So make this however long you need for the Truenas to
   boot.)

Now for your other VMs, set the boot order greater than 1, and they
will boot automatically after 150s allowance for truenas to start.
That should be enough time so that truenas boots and starts the
storage shares.

## Add physical drives

So far you have only created the shares on a temporary `test` pool.
Now its time to upgrade your truenas VM to use real physical drives
and to create a permanent ZFS pool.

You have two options for hard drive passthrough:

 * NVME PCI passthrough
 * Per device passthrough (supports any drive type, like SATA or NVME)

### PCI passthrough

To add PCI devices directly, your system must support IOMMU.

To enable IOMMU, you must enable it in the grub bootloader config. Log
in to the Proxmox console via SSH, and edit the file
`/etc/default/grub`. Change the following line to add the iommu
support:

```
GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on quiet"
```

(if you are using an AMD system, use `amd_iommu=on` instead)

Run `update-grub`, then reboot the proxmox host to enable the setting.

Once rebooted, open the dashboard:

 * Go to the truenas VM `Hardware` page
 * Click `Add`
 * Click `PCI Device`
 * Click `Raw Device`
 * Find the PCI device for your NVME drive in the list
 * Click `All Functions` for good measure
 * Click `Add`
 * Repeat these steps to add all the physical PCI devices

### HDD passthrough

If your system does not support PCI passthrough, or if you are using a
JBOD sata controller, you may alternatively passthrough each block
device individually. This must be configured through the terminal
following the [Passthrough Physical Disk to Virtual Machine
guide](https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)


## Add serial numbers to the physical drives

TrueNAS requires each drive in your storage pools to have a unique
serial number. By default, Proxmox does not assign any serial numbers
to the disks being passthrough, and there also does not appear to be
any way to add a serial using the dashboard. You must edit the VM
configuration file by hand:

 * Login to the Proxmox console, either by SSH, or through the `Console` tab.
 * Use a text editor (`nano`) to edit the VM configuration file:
   `/etc/pve/nodes/{host}/qemu-server/{vm_id}.conf`
 * Find each line that starts with `scsi0`, add append the following
   text: `,serial=0000` where `0000` should match the physical serial
   number of the device. Confirm the serial number with `lshw`
 * In the dashboard navigate to the VM's `Hardware` page and verify
   the serials have been added
 * Reboot the truenas VM and the drives should be detected, and you
   can setup your new pool the same way as before
