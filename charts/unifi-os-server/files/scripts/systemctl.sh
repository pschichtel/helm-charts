#!/bin/bash
# systemctl replacement for the unifi-core container (installed over
# /bin/systemctl by run-unifi-core.sh; /sbin/{reboot,poweroff,halt} link to it).
# There is no systemd in the pod. Rebooting, or restarting/stopping one of the
# UniFi services, restarts all containers of the pod: the pod shares one process
# namespace, so a SIGTERM to every process ends every container's main process,
# and the kubelet starts them again. "restart cron" (ubnt-systool's last step
# after changing the time zone) publishes core's zone to /run/uos-tz for the
# other containers (see use_shared_timezone in lib.sh). Everything else
# succeeds without effect (enable, mask, transient units, ...).

publish_timezone() {
  mkdir -p /run/uos-tz
  cp /etc/localtime /run/uos-tz/.localtime && mv -f /run/uos-tz/.localtime /run/uos-tz/localtime
  cp /etc/timezone /run/uos-tz/.timezone && mv -f /run/uos-tz/.timezone /run/uos-tz/timezone
}

restart_pod() {
  echo "systemctl-shim: $*: restarting all containers" >&2
  # delayed and detached, so that the caller (an API request) can still answer
  ( sleep 3; kill -TERM -1 ) </dev/null >/dev/null 2>&1 &
  disown
}

# first non-option argument is the verb (or the name we were called by)
verb=$(basename "$0")
units=()
for a in "$@"; do
  [[ $a == -* ]] && continue
  if [ "$verb" = systemctl ] || [ "$verb" = systemctl.sh ]; then verb=$a; else units+=("$a"); fi
done

case $verb in
  reboot | poweroff | halt) restart_pod "$verb" ;;
  restart | try-restart | reload-or-restart | try-reload-or-restart | stop | kill | reload)
    for u in "${units[@]}"; do
      case ${u%.service} in
        nginx) [ "$verb" = stop ] || nginx -s reload 2>/dev/null || nginx 2>/dev/null ;;
        cron) [ "$verb" = restart ] && publish_timezone ;;
        unifi-core | unifi | ulp-go | uid-agent | ucs-agent | unifi-directory | \
          unifi-identity-update | uos-agent | uos-discovery-client)
          [ "$verb" = reload ] || { restart_pod "$verb $u"; break; } ;;
      esac
    done
    ;;
  is-system-running) echo running ;;
  is-active) for _ in "${units[@]}"; do echo active; done ;;
  is-enabled) for _ in "${units[@]}"; do echo enabled; done ;;
esac
exit 0
