#!/bin/bash
### restic_backup.sh
### See the blog post: https://blog.rymcg.tech/blog/linux/restic_backup/
## Restic Backup Script for S3 cloud storage (and compatible APIs).
## Install the `restic` package with your package manager.
## Copy this script to any directory, and change the permissions:
##   chmod 0700 rclone_backup.sh
## Put all your configuration directly in this script.
## SAVE A COPY of this configured script to a safe place in the case of disaster.
## Consider creating an alias in your .bashrc: alias backup=<path-to-this-script>
## Edit the variables below (especially the ones like change-me-change-me-change-me):  
## WARNING: This will include plain text passwords for restic and S3

## Which directories do you want to backup from?
## Specify one or more directories inside single parentheses (bash array) separated by spaces:
RESTIC_BACKUP_PATHS=(${HOME}/Documents ${HOME}/Music ${HOME}/Sync)

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

commands=(init backup forget prune systemd_setup status logs snapshots restore help)

run_restic() {
    export RESTIC_PASSWORD
    export AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}
    export AWS_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}
    set -x
    restic -v -r s3:https://${S3_ENDPOINT}/${S3_BUCKET} $@
}

init() { # : Initialize restic repository
    run_restic init
}

backup() { # : Run backup now
    run_restic backup --tag ${BACKUP_TAG} ${RESTIC_BACKUP_PATHS[@]}
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

logs() { # : Show recent service logs
    SERVICE_NAME=restic_backup.${S3_ENDPOINT}-${S3_BUCKET}
    set -x
    journalctl --user --unit ${SERVICE_NAME} --since yesterday
}

help() { # : Show this help
    echo "## restic_backup.sh Help:"
    echo -e "# subcommand [ARG1] [ARG2]\t#  Help Description" | expand -t35
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

