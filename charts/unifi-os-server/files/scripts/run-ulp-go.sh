#!/bin/bash
# ulp-go (Go), foreground, starts as root, prepares its directories and drops to the app user (see as-user.sh).
set -e

source /scripts/lib.sh
use_shared_timezone
render_go_props ulp-go ulp-go
source /usr/lib/ulp-go/scripts/envs.sh
export CAPTURE_DIR="${ULP_WS_DIR}/activities_resource"
export TMPDIR="${ULP_TMP_DIR}"
cd "${ULP_DATA_DIR}"
exec /scripts/as-user.sh ulp-go \
  /data/ulp-go \
  /data/ulp-go/ws \
  /data/ulp-go/tmp \
  /srv/ulp-go \
  /run/ulp-go \
  -- /usr/sbin/ulp-go-app --prop /usr/lib/ulp-go/config.props
