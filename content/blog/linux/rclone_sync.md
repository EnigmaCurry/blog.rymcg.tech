---
title: "Continuous immediate file sync with Rclone"
date: 2021-03-03T00:01:00-06:00
tags: ['linux']
---

[RClone](https://rclone.org/) is an excellent, open-source, file synchronization
tool. It supports [a lot of different service
backends](https://rclone.org/overview/). However, [it does not automatically
sync when files are saved](https://github.com/rclone/rclone/issues/249), like
the (proprietary) Dropbox tool can. Instead, the common suggestion is to run
rclone in a cron job, but this means that your files will only be synchronized
as often as the cron job runs.

We can improve this, with a script that uses
[inotifywait](https://linux.die.net/man/1/inotifywait) to run immediately
whenever files are changed. Furthermore, we can run the script in a User systemd
unit so that syncrhonizations occur all of the time, even after a system reboot.
Optional Desktop notifications, will give you extra confidence that the script
is functional. (Otherwise you can check the systemd log for the verbose rclone
output.)

All of the documentation is included in the script itself, just copy and save
this script as `sync.sh` anywhere on your system, read it, then edit:

```sh
#!/bin/bash
## One-way, immediate, continuous, recursive, directory synchronization
##  to a remote Rclone URL. ( S3, SFTP, FTP, WebDAV, Dropbox, etc. )
## Optional desktop notifications on sync events or errors.
## Useful only for syncing a SMALL number of files (< 8192).
##  (See note in `man inotifywait` under `--recursive` about raising this limit.)
## Think use-case: Synchronize Traefik TLS certificates file (acme.json)
## Think use-case: Synchronize Keepass (.kdbx) database file immediately on save.
## Think use-case: Live edit source code and push to remote server

## This is NOT a backup tool! 
## It will not help you if you delete your files or if they become corrupted.

## Setup: Install `rclone` from package manager.
## Run: `rclone config` to setup the remote, including the full remote
##   subdirectory path to sync to.
## MAKE SURE that the remote (sub)directory is EMPTY
##   or else ALL CONTENTS WILL BE DELETED by rclone when it syncs.
## If unsure, add `--dry-run` to the RCLONE_CMD variable below, 
##   to simulate what would be copied/deleted. 
## Copy this script any place, and make it executable: `chown +x sync.sh`
## Edit all the variables below, before running the script.
## Run: `./sync.sh systemd_setup` to create and enable systemd service.
## Run: `journalctl --user --unit rclone_sync.${RCLONE_REMOTE}` to view the logs.

## Edit the variables below, according to your own environment:

# RCLONE_SYNC_PATH: The path to COPY FROM (files are not synced TO here):
RCLONE_SYNC_PATH="/home/user/dav-sync"

# RCLONE_REMOTE: The rclone remote name to synchronize with.
# Identical to one of the remote names listed via `rclone listremotes`.
# Make sure to include the final `:` in the remote name, which
#   indicates to sync/delete from the same (sub)directory as defined in the URL.
# (ALL CONTENTS of the remote are continuously DELETED
#  and replaced with the contents from RCLONE_SYNC_PATH)
RCLONE_REMOTE="my-webdav-remote:"

# RCLONE_CMD: The sync command and arguments:
RCLONE_CMD="rclone -v sync ${RCLONE_SYNC_PATH} ${RCLONE_REMOTE}"

# WATCH_EVENTS: The file events that inotifywait should watch for:
WATCH_EVENTS="modify,delete,create,move"

# SYNC_DELAY: Wait this many seconds after an event, before synchronizing:
SYNC_DELAY=5

# SYNC_INTERVAL: Wait this many seconds between forced synchronizations:
SYNC_INTERVAL=3600

# NOTIFY_ENABLE: Enable Desktop notifications
NOTIFY_ENABLE=true

# SYNC_SCRIPT: dynamic reference to the current script path
SYNC_SCRIPT=$(realpath $0)

notify() {
    MESSAGE=$1
    if test ${NOTIFY_ENABLE} = "true"; then
        notify-send "rclone ${RCLONE_REMOTE}" "${MESSAGE}"
    fi
}

rclone_sync() {
    set -x
    # Do initial sync immediately:
    notify "Startup"
    ${RCLONE_CMD}
    # Watch for file events and do continuous immediate syncing
    # and regular interval syncing:
    while [[ true ]] ; do
	inotifywait --recursive --timeout ${SYNC_INTERVAL} -e ${WATCH_EVENTS} \
		    ${RCLONE_SYNC_PATH} 2>/dev/null
	if [ $? -eq 0 ]; then
	    # File change detected, sync the files after waiting a few seconds:
	    sleep ${SYNC_DELAY} && ${RCLONE_CMD} && \
		notify "Synchronized new file changes"
	elif [ $? -eq 1 ]; then
	    # inotify error occured
	    notify "inotifywait error exit code 1"
        sleep 10
	elif [ $? -eq 2 ]; then
	    # Do the sync now even though no changes were detected:
	    ${RCLONE_CMD}
	fi
    done
}

systemd_setup() {
    set -x
    if loginctl show-user ${USER} | grep "Linger=no"; then
	    echo "User account does not allow systemd Linger."
	    echo "To enable lingering, run as root: loginctl enable-linger $USER"
	    echo "Then try running this command again."
	    exit 1
    fi
    mkdir -p ${HOME}/.config/systemd/user
    SERVICE_FILE=${HOME}/.config/systemd/user/rclone_sync.${RCLONE_REMOTE}.service
    if test -f ${SERVICE_FILE}; then
	    echo "Unit file already exists: ${SERVICE_FILE} - Not overwriting."
    else
	    cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=rclone_sync ${RCLONE_REMOTE}

[Service]
ExecStart=${SYNC_SCRIPT}

[Install]
WantedBy=default.target
EOF
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now rclone_sync.${RCLONE_REMOTE}
    systemctl --user status rclone_sync.${RCLONE_REMOTE}
    echo "You can watch the logs with this command:"
    echo "   journalctl --user --unit rclone_sync.${RCLONE_REMOTE}"
}

if test $# = 0; then
    rclone_sync
else
    CMD=$1; shift;
    ${CMD} $@
fi
```
