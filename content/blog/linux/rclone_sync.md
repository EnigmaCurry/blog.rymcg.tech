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
[inotifywait](https://linux.die.net/man/1/inotifywait) to run
immediately whenever files are changed. Furthermore, we can run the
script in a [User systemd
unit](https://wiki.archlinux.org/title/Systemd/User) so that
syncrhonizations occur all of the time, even after a system reboot.
Optional Desktop notifications, will give you extra confidence that
the script is functional. (Otherwise you can check the systemd log for
the verbose rclone output.)

All of the documentation is included in the script itself, just copy and save
this script as `sync.sh` anywhere on your system, read it, then edit:


 * [Download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/rclone/rclone_sync.sh)

{{< code file="/src/rclone/rclone_sync.sh" language="shell" >}}
