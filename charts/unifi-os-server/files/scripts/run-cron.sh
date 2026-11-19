#!/bin/bash
# cron: the image's scheduled jobs, foreground. Nothing starts cron otherwise
# (no systemd). The jobs that matter here:
#   /etc/cron.hourly/logrotate  rotates /data/unifi-core/logs/nginx-*.log; the
#                               postrotate signals nginx via /run/nginx.pid
#                               (shared /run and process namespace)
#   /etc/cron.d/uos-agent       hourly alarm cleanup, POST to uos-agent :11010
#   /etc/cron.d/uos             weekly "uos system prune": deletes downloaded
#                               packages older than 7 days in /data/uos/downloads
set -e

# Host maintenance that does not apply to a container: ext4 scrubbing,
# unattended apt runs, dpkg status backups.
rm -f /etc/cron.d/e2scrub_all /etc/cron.daily/apt-compat /etc/cron.daily/dpkg

exec cron -f
