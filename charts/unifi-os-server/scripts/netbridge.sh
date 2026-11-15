#!/bin/bash
# Makes the loopback addresses the apps hard-code work across containers.
#
# The UniFi OS apps talk to each other via 127.0.0.1:<port> (many of these are
# compiled into the binaries and cannot be configured). In a systemd system
# they share one network stack; here every service has its own container, so
# each container runs this script before its app:
#
#  * outbound: for every port owned by ANOTHER service, listen on
#    127.0.0.1:<port> and forward to <owner>:<port>
#  * inbound:  for ports this service binds on loopback only (flag "lo"),
#    listen on the container's own IP and forward to 127.0.0.1:<port>, so the
#    app sees the peer as 127.0.0.1 (matters for http.trust.hosts etc.)
#
# Requires NETBRIDGE_SELF=<compose service name>. Uses only socat/setpriv from
# the stock image. Forwarders run as `nobody` (NET_BIND_SERVICE kept for 80/443)
# and are restarted if they die. Unix sockets need nothing: /run is a shared
# volume.
#
# Table: <port>:<owner service>[:lo]  (lo = owner binds loopback only)
# Ports with no owner in this stack (credential server 9580, access 12080,
# ...) are intentionally absent: they stay "connection refused" as before.
PORTS="
11081:unifi-core:lo
11051:unifi-core:lo
80:unifi-core
443:unifi-core
11084:unifi-core
8081:unifi:lo
8080:unifi
8443:unifi
8843:unifi
8880:unifi
6789:unifi
28082:unifi
9080:ulp-go:lo
9443:ulp-go
6080:uid-agent:lo
6443:uid-agent
9680:ucs-agent:lo
13080:unifi-directory:lo
9081:unifi-identity-update:lo
11010:uos-agent:lo
11011:uos-agent:lo
11002:uos-discovery-client:lo
"

: "${NETBRIDGE_SELF:?set NETBRIDGE_SELF to the compose service name}"
self_ip=$(hostname -i | awk '{print $1}')

fwd() { # <listen addr> <port> <target host> <target port>
  (
    while :; do
      setpriv --reuid=65534 --regid=65534 --clear-groups \
        --inh-caps=+net_bind_service --ambient-caps=+net_bind_service \
        socat "TCP-LISTEN:$2,bind=$1,fork,reuseaddr" "TCP:$3:$4"
      sleep 3
    done
  ) &
}

for entry in $PORTS; do
  IFS=: read -r port owner flag <<<"$entry"
  if [ "$owner" = "$NETBRIDGE_SELF" ]; then
    [ "$flag" = lo ] && fwd "$self_ip" "$port" 127.0.0.1 "$port"
  else
    fwd 127.0.0.1 "$port" "$owner" "$port"
  fi
done
