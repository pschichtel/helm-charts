#!/bin/bash
# Usage: as-user.sh <user> [<dir>...] -- <command> [args...]
# List every directory explicitly, parents first (mkdir -p creates missing
# parents as root; only listed dirs get chowned).
# Runs as root (container entrypoint): creates the given directories, makes
# <user> their owner (recursively only if the top-level owner is wrong, so
# restarts stay cheap), then exec()s the command with <user>'s uid/gid and
# supplementary groups from /etc/group. exec, not runuser, so the app is the
# container's main process and receives signals directly.
set -e

user=$1; shift
dirs=()
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do dirs+=("$1"); shift; done
[ "$1" = "--" ] || { echo "as-user.sh: missing --" >&2; exit 64; }
shift

uid=$(id -u "$user")
for d in "${dirs[@]}"; do
  mkdir -p "$d"
  [ "$(stat -c %u "$d")" = "$uid" ] || chown -R "$user:" "$d"
done

exec setpriv --reuid="$user" --regid="$user" --init-groups "$@"
