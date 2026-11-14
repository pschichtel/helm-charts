#!/bin/bash
# unifi-identity-update (Go), foreground.
set -e

source /usr/lib/unifi-identity-update/scripts/envs.sh

# --- wait for postgres
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

# --- first boot: data dirs + pg role/db bootstrap (`unifi-identity-update init`)
mkdir -p "${IDENTITY_DATA_DIR}"/log "${IDENTITY_DATA_DIR}"/ws "${IDENTITY_DATA_DIR}"/tmp
chown -R ucs-update:ucs-update /data/unifi-identity-update 2>/dev/null || true
# --- point the app at the shared postgres service (BEFORE pre-start: its psql bootstrap uses these)
sed -i 's|^db.host = .*|db.host = postgres|; s|^db.port = .*|db.port = 5432|' /usr/lib/unifi-identity-update/config.props
export PGHOST=postgres PGPORT=5432
bash /usr/lib/unifi-identity-update/scripts/service/pre-start.sh || true

export TMPDIR="${IDENTITY_TMP_DIR}"
cd "${IDENTITY_DATA_DIR}"
exec runuser -u ucs-update -- /usr/sbin/unifi-identity-update-app --prop /usr/lib/unifi-identity-update/config.props
