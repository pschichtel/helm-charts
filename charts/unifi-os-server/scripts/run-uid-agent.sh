#!/bin/bash
# uid-agent (Go), foreground.
set -e

# --- console identity metadata (see uos-meta.sh)
bash /scripts/uos-meta.sh || true
source /usr/lib/uid-agent/scripts/envs.sh

# --- wait for postgres
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

# --- first boot: data dirs + pg role/db bootstrap (`uid-agent init`)
mkdir -p "${UID_AGENT_DATA_DIR}"/log "${UID_AGENT_DATA_DIR}"/ws "${UID_AGENT_DATA_DIR}"/tmp
# json-rpc socket dir on the shared /run volume
mkdir -p /run/uid
chown -R uid:uid /data/uid /srv/uid /run/uid 2>/dev/null || true
# --- point the app at the shared postgres service (BEFORE pre-start: its psql bootstrap uses these)
sed -i 's|^db.host = .*|db.host = postgres|; s|^db.port = .*|db.port = 5432|' /usr/lib/uid-agent/config.props
export PGHOST=postgres PGPORT=5432
bash /usr/lib/uid-agent/scripts/service/pre-start.sh || true

export TMPDIR="${UID_AGENT_TMP_DIR}"
cd "${UID_AGENT_DATA_DIR}"
exec runuser -u uid -- /usr/sbin/uid-agent-app --props /usr/lib/uid-agent/config.props
