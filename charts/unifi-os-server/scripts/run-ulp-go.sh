#!/bin/bash
# ulp-go: ULP app framework (Go), foreground.
set -e

source /usr/lib/ulp-go/scripts/envs.sh

# --- wait for postgres
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

# --- first boot: data dirs + pg role/db bootstrap (pre-start runs `ulp init`)
mkdir -p "$ULP_DATA_DIR"/log "$ULP_DATA_DIR"/ws "$ULP_DATA_DIR"/tmp
chown -R ulp-go:ulp-go /data/ulp-go /srv/ulp-go 2>/dev/null || true
# --- fix broken xorm-fork GetColumns SQL template (zero-length binary patch, idempotent)
bash /scripts/patch-ulp-go-app.sh
# --- point the app at the shared postgres service (BEFORE pre-start: its psql bootstrap uses these)
sed -i 's|^db.host = .*|db.host = postgres|; s|^db.port = .*|db.port = 5432|' /usr/lib/ulp-go/config.props
export PGHOST=postgres PGPORT=5432
bash /usr/lib/ulp-go/scripts/service/pre-start.sh || true

export TMPDIR="${ULP_TMP_DIR}"
export CAPTURE_DIR="${ULP_WS_DIR}/activities_resource"
cd "${ULP_DATA_DIR}"
exec runuser -u ulp-go -- /usr/sbin/ulp-go-app --prop /usr/lib/ulp-go/config.props
