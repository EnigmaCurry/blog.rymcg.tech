---
title: "Daily backups to S3 with Restic and systemd timers"
date: 2022-01-17T00:01:00-06:00
tags: ['linux']
---

[Restic](https://restic.net/) is a modern backup program that can archive your
files onto many different cloud and network storage locations, and to help
restore your files in case of disaster. This article will show you how to backup
one or more user directories to S3, using restic and systemd.

## Choose an S3 vendor and create a bucket

Restic supports many different storage mechanisms, but this article and
associated scripts will only focus on using S3 storage (AWS or S3 API
compatible endpoint). You can choose from many different storage vendors: AWS,
DigitalOcean, Backblaze, Wasabi, Minio etc.

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

 * Open your text editor and create a new file named `restic_backup.sh`. You can
   save it wherever you want, but one suggestion is to put it in
   `${HOME}/.config/restic_backup/restic_backup.sh`
 * Copy the following script into your clipboard and paste it into the new file.

{{< code file="/src/systemd/restic_backup.sh" language="shell" >}}

 * Review and edit all of the variables at the top of the file, and save the
   file.
 * Change the permissions on the file to be executable and private:
 
```
chmod 0700 ${HOME}/.config/restic_backup/restic_backup.sh
```

## Usage

 * To make using the script easier, create this BASH alias in your `~/.bashrc`:
 
```
## backup alias for the restic backup script:
alias backup=${HOME}/.config/restic_backup/restic_backup.sh
```
 * Restart the shell / close and reopen your terminal.
 * Run the script alias, to see the help screen: `backup`

```
## restic_backup.sh Help:
# subcommand [ARG1] [ARG2]         #  Help Description
init                               #  Initialize restic repository in ${RESTIC_BACKUP_PATH} 
backup                             #  Run backup now 
forget                             #  Apply the configured data retention policy to the backend 
prune                              #  Remove old snapshots from repository 
systemd_setup                      #  Schedule backups by installing systemd timers 
status                             #  Show the last and next backup/prune times 
logs                               #  Show recent service logs 
snapshots                          #  List all snapshots 
restore [SNAPSHOT] [ROOT_PATH]     #  Restore data from snapshot (default 
help                               #  Show this help 
```

 * Initialize the restic repository:
 
```
backup init
```

 * Run the first backup manually:
 
```
backup backup
```

 * Install the systemd service, scheduling the backup to automatically run
   daily:
 
```
backup systemd_setup
```

 * Check the status (See the next and previous timers):
 
```
backup status
```

 * List snapshots
```
backup snapshots
```

 * Restore from the latest snapshot

```
backup restore 
```

 * Restore from a different snapshot (`xxxxxx`), to an alternative directory
   (`~/copy`):
 
```
backup restore xxxxxx ~/copy
```

 * Prune the repository, cleaning up storage space, and deleting old snapshots
   that are past the time of your data retention policy. (This is scheduled to
   be run automatically once a month:)

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
