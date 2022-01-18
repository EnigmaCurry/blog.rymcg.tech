---
title: "Daily backups to S3 with Restic and systemd timers"
date: 2022-01-17T00:01:00-06:00
tags: ['linux']
---

[Restic](https://restic.net/) is a modern backup program that can archive your
files onto many different cloud and network storage locations, and to help
restore your files in case of disaster. This article will show you how to backup
a single user directory to S3, using restic and systemd.

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
compatible API, with a pricing and usage model perfect for backups.

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
   
## Download the backup script

Install `restic` [with your package
manager](https://restic.readthedocs.io/en/stable/020_installation.html).

Here is an all-in-one script that can setup and run your restic backups
automatically on a daily basis, all from your user account (No root needed).

 * Download (copy and paste) the script to any place you like (suggestion:
`${HOME}/.config/restic_backup/restic_backup.sh`)
 * Change the permissions: `chmod 0700 <PATH-TO-SCRIPT>`

```sh
#!/bin/bash
## restic_backup.sh - https://blog.rymcg.tech/blog/linux/restic_backup/
## Restic Backup Script for S3 cloud storage (and compatible APIs)
## Install the `restic` package with your package manager
## Copy this script to any directory, and change the permissions:
##   chmod 0700 rclone_backup.sh
## Put all your configuration directly in this script.
## SAVE A COPY of this configured script to a safe place in the case of disaster.
## Edit the variables below:

## Which directory do you want to backup from?
RESTIC_BACKUP_PATH=${HOME}/Sync

## Create a secure encryption passphrase for your restic data:
## WRITE THIS PASSWORD DOWN IN A SAFE PLACE:
RESTIC_PASSWORD=change-me-change-me-change-me

## Enter the bucket name, endpoint, and credentials:
S3_BUCKET=change-me-change-me-change-me
S3_ENDPOINT=s3.us-west-1.wasabisys.com
S3_ACCESS_KEY_ID=change-me-change-me-change-me
S3_SECRET_ACCESS_KEY=change-me-change-me-change-me

## Restic data retention policy:
# https://restic.readthedocs.io/en/stable/060_forget.html#removing-snapshots-according-to-a-policy
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=6
RETENTION_YEARS=3

## The tag to apply to all snapshots made by this script:
BACKUP_TAG=${BASH_SOURCE}

commands=(init backup forget prune systemd_setup status snapshots restore help)

run_restic() {
    export RESTIC_PASSWORD
    export AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}
    export AWS_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}
    set -x
    restic -v -r s3:https://${S3_ENDPOINT}/${S3_BUCKET} $@
}

init() { # : Initialize restic repository in ${RESTIC_BACKUP_PATH}
    mkdir -p ${RESTIC_BACKUP_PATH}
    run_restic init
}

backup() { # : Run backup now
    run_restic backup --tag ${BACKUP_TAG} ${RESTIC_BACKUP_PATH}
}

prune() { # : Remove old snapshots from repository
    run_restic prune
}

forget() { # : Apply the configured data retention policy to the backend
    run_restic forget --tag ${BACKUP_TAG} --group-by "paths,tags" \
           --keep-daily $RETENTION_DAYS --keep-weekly $RETENTION_WEEKS \
           --keep-monthly $RETENTION_MONTHS --keep-yearly $RETENTION_YEARS
}

snapshots() { # : List all snapshots
    run_restic snapshots
}

restore() { # [SNAPSHOT] [ROOT_PATH] : Restore data from snapshot (default: 'latest')
    SNAPSHOT=${1:-latest}; ROOT_PATH=${2:-/};
    if test -d ${ROOT_PATH} && [[ ${ROOT_PATH} != "/" ]]; then
        echo "ERROR: Non-root restore path already exists: ${ROOT_PATH}"
        echo "Choose a non-existing directory name and try again. Exiting."
        exit 1
    fi
    read -p "Are you sure you want to restore all data from snapshot '${SNAPSHOT}' (y/N)? " yes_no
    if [[ ${yes_no,,} == "y" ]] || [[ ${yes_no,,} == "yes" ]]; then
        run_restic restore -t ${ROOT_PATH} ${SNAPSHOT}
    else
        echo "Exiting." && exit 1
    fi
}

systemd_setup() { # : Schedule backups by installing systemd timers
    if loginctl show-user ${USER} | grep "Linger=no"; then
	    echo "User account does not allow systemd Linger."
	    echo "To enable lingering, run as root: loginctl enable-linger $USER"
	    echo "Then try running this command again."
	    exit 1
    fi
    mkdir -p ${HOME}/.config/systemd/user
    SERVICE_NAME=restic_backup.${S3_ENDPOINT}-${S3_BUCKET}
    SERVICE_FILE=${HOME}/.config/systemd/user/${SERVICE_NAME}.service
    TIMER_FILE=${HOME}/.config/systemd/user/${SERVICE_NAME}.timer
    cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE})
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath ${BASH_SOURCE}) backup
ExecStartPost=$(realpath ${BASH_SOURCE}) forget
EOF
    cat <<EOF > ${TIMER_FILE}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE}) daily backups
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
EOF
    PRUNE_NAME=restic_backup.prune.${S3_ENDPOINT}-${S3_BUCKET}
    PRUNE_FILE=${HOME}/.config/systemd/user/${PRUNE_NAME}.service
    PRUNE_TIMER_FILE=${HOME}/.config/systemd/user/${PRUNE_NAME}.timer
    cat <<EOF > ${PRUNE_FILE}
[Unit]
Description=restic_backup prune $(realpath ${BASH_SOURCE})
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath ${BASH_SOURCE}) prune
EOF
    cat <<EOF > ${PRUNE_TIMER_FILE}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE}) monthly pruning
[Timer]
OnCalendar=*-*-01 00:02:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now ${SERVICE_NAME}.timer
    systemctl --user enable --now ${PRUNE_NAME}.timer
    systemctl --user status ${SERVICE_NAME} --no-pager
    systemctl --user status ${PRUNE_NAME} --no-pager
    echo "You can watch the logs with this command:"
    echo "   journalctl --user --unit ${SERVICE_NAME}"
}

status() { # : Show the last and next backup/prune times 
    SERVICE_NAME=restic_backup.${S3_ENDPOINT}-${S3_BUCKET}
    PRUNE_NAME=restic_backup.prune.${S3_ENDPOINT}-${S3_BUCKET}
    set -x
    systemctl --user list-timers ${SERVICE_NAME} --no-pager
    systemctl --user list-timers ${PRUNE_NAME} --no-pager
}

help() { # : Show this help
    echo "Subcommand Help:"
    for cmd in "${commands[@]}"; do
        annotation=$(grep -E "^${cmd}\(\) { # " ${BASH_SOURCE} | sed "s/^${cmd}() { # \(.*\)/\1/")
        args=$(echo ${annotation} | cut -d ":" -f1)
        description=$(echo ${annotation} | cut -d ":" -f2)
        echo -e "${cmd} ${args}\t# ${description} " | expand -t35
    done
}

main() {
    if [[ $(stat -c "%a" ${BASH_SOURCE}) != "700" ]]; then
        echo "Incorrect permissions on script. Run: "
        echo "  chmod 0700 $(realpath ${BASH_SOURCE})"
        exit 1
    fi

    if test $# = 0; then
        help
    else
        CMD=$1; shift;
        if [[ " ${commands[*]} " =~ " ${CMD} " ]]; then
            ${CMD} $@
        else
            echo "Unknown command: ${CMD}" && exit 1
        fi
    fi
}

main $@
```

## Usage

 * Procure your S3 Bucket, credentials, and endpoint URL.
 * Save the script to any directory you like.
 * Change the permissions on the script: `chmod 0700 restic_backup.sh`
 * Edit all the variables at the top of your `restic_backup.sh` file.
 
 * Initialize the restic repository:
 
```
./restic_backup.sh init
```

 * Run the first backup manually:
 
```
./restic_backup.sh backup
```

 * Install the systemd service, scheduling the backup to automatically run
   daily:
 
```
./restic_backup.sh systemd_setup
```

 * Check the status (See the next and previous timers):
 
```
./restic_backup.sh status
```

 * List snapshots
```
./restic_backup.sh snapshots
```

 * Restore from the latest snapshot

```
./restic_backup.sh restore 
```

 * Restore from a different snapshot (`xxxxxx`), to an alternative directory
   (`~/copy`):
 
```
./restic_backup.sh restore xxxxxx ~/copy
```

 * Prune the repository, cleaning up storage space, and deleting old snapshots
   that are past the time of your data retention policy. (This is scheduled to
   be run automatically once a month:)

```
./restic_backup.sh prune
```
