#!/bin/bash
# uos-agent (Rust, runs as root like the stock systemd unit).
set -e
/scripts/netbridge.sh
exec /usr/bin/uos-agent
