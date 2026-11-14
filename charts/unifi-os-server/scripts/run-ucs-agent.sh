#!/bin/bash
# ucs-agent (Go), foreground.
set -e

# --- console identity metadata (see uos-meta.sh)
bash /scripts/uos-meta.sh || true
source /usr/lib/ucs-agent/scripts/envs.sh

# --- wait for postgres
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

# --- first boot: data dirs + pg role/db bootstrap (`ucs-agent init`)
mkdir -p "${IDENTITY_DATA_DIR}"/log "${IDENTITY_DATA_DIR}"/ws "${IDENTITY_DATA_DIR}"/tmp
chown -R ucs-agent:ucs-agent /data/ucs-agent 2>/dev/null || true
# --- point the app at the shared postgres service (BEFORE pre-start: its psql bootstrap uses these)
sed -i 's|^db.host = .*|db.host = postgres|; s|^db.port = .*|db.port = 5432|' /usr/lib/ucs-agent/config.props
export PGHOST=postgres PGPORT=5432
bash /usr/lib/ucs-agent/scripts/service/pre-start.sh || true

export TMPDIR="${IDENTITY_TMP_DIR}"
cd "${IDENTITY_DATA_DIR}"
exec runuser -u ucs-agent -- /usr/sbin/ucs-agent-app --prop /usr/lib/ucs-agent/config.props
