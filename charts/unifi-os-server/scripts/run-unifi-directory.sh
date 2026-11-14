#!/bin/bash
# unifi-directory (Go), foreground.
set -e

source /usr/lib/unifi-directory/scripts/envs.sh

# --- wait for postgres
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

# --- first boot: data dirs + pg role/db bootstrap (`unifi-directory init`)
mkdir -p "${DIRECTORY_DATA_DIR}"/log "${DIRECTORY_DATA_DIR}"/ws "${DIRECTORY_DATA_DIR}"/tmp
chown -R unifi-directory:unifi-directory /data/unifi-directory 2>/dev/null || true
# --- point the app at the shared postgres service (BEFORE pre-start: its psql bootstrap uses these)
sed -i 's|^db.host = .*|db.host = postgres|; s|^db.port = .*|db.port = 5432|' /usr/lib/unifi-directory/config.props
export PGHOST=postgres PGPORT=5432
bash /usr/lib/unifi-directory/scripts/service/pre-start.sh || true

export TMPDIR="${DIRECTORY_TMP_DIR}"
cd "${DIRECTORY_DATA_DIR}"
exec runuser -u unifi-directory -- /usr/sbin/unifi-directory-app --prop /usr/lib/unifi-directory/config.props
