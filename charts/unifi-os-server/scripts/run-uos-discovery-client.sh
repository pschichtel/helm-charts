#!/bin/bash
# uos-discovery-client (Rust, runs as root like the stock systemd unit).
set -e
/scripts/netbridge.sh
exec /usr/bin/uos-discovery-client
