---
title: "Daily backups to S3 with Restic and systemd timers"
date: 2022-01-17T00:01:00-06:00
tags: ['linux']
---

[Restic](https://restic.net/) is a modern backup program that can archive your
files onto many different cloud and network storage locations, and to help
restore your files in case of disaster. This article will show you how to backup
one or more user directories to S3 cloud storage, using restic and systemd.

## Choose an S3 vendor and create a bucket

Restic supports many different storage mechanisms, but this article and
associated scripts will only focus on using S3 storage (AWS or S3 API
compatible endpoint). You can choose from many different storage vendors: AWS,
DigitalOcean, Backblaze, Wasabi, Minio etc.

You'll need to gather the following information from your S3 provider:

 * `S3_BUCKET` - the name of the S3 bucket
 * `S3_ENDPOINT` the domain name of the S3 server
 * `S3_ACCESS_KEY_ID` The S3 access ID
 * `S3_SECRET_ACCESS_KEY` The S3 secret key

### Example with Minio

Minio is an open-source self-hosted S3 server. You can easily install Minio on
your docker server. See the instructions for
[d.rymcg.tech](https://github.com/EnigmaCurry/d.rymcg.tech) and then install
[minio](https://github.com/EnigmaCurry/d.rymcg.tech/tree/master/minio). 

Follow [the instructions for creating a bucket, policy, and
credentials](https://github.com/EnigmaCurry/d.rymcg.tech/tree/master/minio#create-a-bucket)

### Example with Wasabi

[Wasabi](https://wasabi.com/) is an inexpensive cloud storage vendor with an S3
compatible API, and with a pricing and usage model perfect for backups.

 * Create a wasabi account and [log in to the console](https://console.wasabisys.com/)
 * Click on `Buckets` in the menu, then click `Create Bucket`. Choose a unique
   name for the bucket. Select the region, then click `Create Bucket`.
 * Click on `Policies` in the menu, then click `Create Policy`. Enter any name
   for the policy, but its easiest to name it the same thing as the bucket. Copy
   and paste the full policy document below into the policy form, replacing
   `BUCKET_NAME` with your chosen bucket name (there are two instances to
   replace in the body).
   
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::BUCKET_NAME"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::BUCKET_NAME/*"
    }
  ]
}
 
```
 * Once the policy document is edited, click `Create Policy`.

 * Click on `Users` in the menu, then click `Create User`. 
 
   * Enter any username you like, but its easiest to name the user the same as
     the bucket.
   * Check the type of access as `Programatic`. 
   * Click `Next`. 
   * Skip the Groups screen. 
   * On the Policies page, click the dropdown called `Attach Policy To User` and
   find the name of the policy you created above. 
   * Click `Next`.
   * Review and click `Create User.`
   * View the Access and Secret keys. Click `Copy Keys To Clipboard`.
   * Paste the keys into a temporary buffer in your editor to save them, you
     will need to copy them into the script that you download in the next
     section.
   * You will need to know the [S3 endpoint URLs for
     wasabi](https://wasabi-support.zendesk.com/hc/en-us/articles/360015106031-What-are-the-service-URLs-for-Wasabi-s-different-storage-regions-)
     later, which are dependent on the Region you chose for the bucket. (eg.
     `s3.us-west-1.wasabisys.com`)
   
## Download and edit the backup script

Install `restic` [with your package
manager](https://restic.readthedocs.io/en/stable/020_installation.html).

Here is an all-in-one script that can setup and run your restic backups
automatically on a daily basis, all from your user account (No root needed).

 * [Download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/systemd/restic_backup.sh)
 * You can save it wherever you want, named whatever you want, but one
   suggestion is to put it in `${HOME}/.config/restic_backup/my_backup.sh`
 * Alternatively, you may copy and paste the entire script into a new file, as
   follows:
 
{{< code file="/src/systemd/restic_backup.sh" language="shell" >}}

 * Review and edit all of the variables at the top of the file, and save the
   file.
 * Change the permissions on the file to be executable and private:
 
```
chmod 0700 ${HOME}/.config/restic_backup/restic_backup.sh
```

 * Consider saving a copy of the final script in your password manager, you will
   need this to recover your files in the event of a disaster.

## Usage

 * To make using the script easier, create this BASH alias in your `~/.bashrc`:
 
```
## 'backup' is an alias to the full path of my personal backup script:
alias backup=${HOME}/.config/restic_backup/my_backup.sh
```

 * Restart the shell or close/reopen your terminal.
 * Run the script alias, to see the help screen: `backup`

```
## restic_backup.sh Help:
# subcommand [ARG1] [ARG2]         #  Help Description
init                               #  Initialize restic repository in ${RESTIC_BACKUP_PATH} 
now                                #  Run backup now 
forget                             #  Apply the configured data retention policy to the backend 
prune                              #  Remove old snapshots from repository 
enable                             #  Schedule backups by installing systemd timers 
disable                            #  Disable scheduled backups and remove systemd timers
status                             #  Show the last and next backup/prune times 
logs                               #  Show recent service logs 
snapshots                          #  List all snapshots 
restore [SNAPSHOT] [ROOT_PATH]     #  Restore data from snapshot (default 
help                               #  Show this help 
```

### Initialize the restic repository
 
```
backup init
```

### Run the first backup manually
 
```
backup now
```

### Install the systemd service

This will schedule the backup to automatically run daily
 
```
backup enable
```

### Check the status 

This will show you the last time and the next time that the timers will run the
backup job:
 
```
backup status
```

### List snapshots

```
backup snapshots
```

### Restore from the latest snapshot 

```
## WARNING: this will reset your files to the backed up versions! 
backup restore 
```

### Restore from a different snapshot

This will restore the snapshot (`xxxxxx`) to an alternative directory (`~/copy`):
 
```
backup restore xxxxxx ~/copy
```

### Prune the repository

This will clean up storage space, and delete old snapshots that are past the
time of your data retention policy. (This is scheduled to be runautomatically
once a month)

```
backup prune
```

## Security considerations

**Be sure not to share your edited script with anyone else, because it now
contains your Restic password and S3 credentials!** 

The script has permissions of `0700` (`-rwx------`) so only your user account
(and `root`) can read the configuraton. However, this also means that *any other
program your user runs can potentially read this file*. 

To limit the possiblity of leaking the passwords, you may consider running this
script in a new user account dedicated to backups. You will also need to take
care that this second user has the correct permissions to read all of the files
that are to be backed up.

## Systemd timers are way better than cron

The backups timers are set to run
[OnCalendar=daily](https://www.freedesktop.org/software/systemd/man/systemd.timer.html#OnCalendar=),
which means to run every single day at midnight. But what if you're running
backups on a laptop, and your laptop wasn't turned on at midnight? Well that's
what
[Persistent=true](https://www.freedesktop.org/software/systemd/man/systemd.timer.html#Persistent=)
is for. Persistent timers remember when they last ran, and if your laptop turns
on and finds that it is past due for running one of the timers it will run it
immediately. So you'll never miss a scheduled backup just because you were
offline.


## Frequently s/asked/expected/ questions

### How do I know its working? 

I hope this script will be reliable for you, but I make no guarantees. You
should check `backup status` and `backup logs` regularly to make sure it's still
working and stable for you in the long term. It might be nice if this script
would email you if there were an error, but this has not been implemented yet.

You should play a mock-disaster scenario: use a second computer and test that
your backup copy of your backup script works (*You did* save a backup of your
script in your password manager, right??):

```
## After copying the script onto a second computer ....
## Test restoring and copying all backed up files into a new directory:
chmod 0700 ./my_backup.sh
./my_backup.sh restore latest ~/restored-files
```

Now you should see all your backed up files in `~/restored-files`, if you do,
you now have evidence that the backup and restore procedures are working.

### I lost my whole computer, how do I get my files back? 

Copy your backup script (the one you saved in your password manager) to any
computer, and run the `restore` command:

```
## After installing your backup script and BASH alias onto a new computer ....
## Restore all files to the same directories they were in before:
backup restore
```

### Can I move or rename the script?

Yes, you can name it whatever you like, and save it in any directory. But
there's some things you need to know about moving it later:

 * The full path of the script is used as the restic backup tag. (Shown via
   `backup snapshots`)
 * This tag is an identifier, so that you can differentiate between backups made
   by this script vs. backups made by running the restic command manually.
 * If you change the path of the script, you will change the backup tag going
   forward.
 * Make sure you update your BASH alias to the new path.
 * The full path of the script is written to the systemd service file, so if you
   change the name or the path, you need to re-enable the service:
   
```
## Reinstall the systemd services after changing the script path:
backup enable
```

### Can I move my backups to a new bucket name or endpoint?

Yes, after copying your bucket data to the new endpoint/name, you will also need
to disable and then re-enable the systemd timers:

 * The name of the systemd service and timer is based upon the bucket name and
   the systemd timer, from the `BACKUP_NAME` variable which is set to
   `restic_backup.${S3_ENDPOINT}-${S3_BUCKET}` by default, so by changing either
   of these variables necessitates changing the name of the systemd service and
   timers.
 * Note: if you only need to change the S3 access or secret keys, but the bucket
   and endpoint stay the same, there's no need to do anything besides editing
   the script.
   
Before making the change, disable the existing timers:

```
backup disable
```

Now edit your script to account for the updated bucket name and/or endpoint.

After making the change, re-enable the timers:

```
backup enable
```

Check the status:

```
backup status
```

### Why suggest the path ~/.config/restic_backup/my_backup.sh?

 * `~/.config` is the default [XDG Base
   Directory](https://wiki.archlinux.org/title/XDG_Base_Directory) which is
   defined as `Where user-specific configurations should be written (analogous
   to /etc).`
 * Normally, scripts wouldn't go into `~/.config` (nor `/etc`), but this script
   is a hybrid config file *and* program script, so it counts as a config file.
 * Each project makes its own subdirectory in `~/.config`, using the project
   name, eg. `restic_backup`. By creating a sub-directory, this allows you to
   save (and use) more than one backup script. (Note: to do so, you would need
   to create an additional BASH alias with a different name.)
 * `my_backup.sh` implies that the script contains personal information and
   should not be shared. Both of which are true! 
 * If you share your `~/.config` publicly (some people I've seen share this
   entire directory on GitHub), you should choose a different path for your
   script!
 * The name and path of the script does not functionally matter.
 
