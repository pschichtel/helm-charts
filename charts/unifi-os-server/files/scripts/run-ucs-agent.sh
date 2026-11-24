#!/bin/bash
# ucs-agent (Go), foreground, starts as root, prepares its directories and drops to the app user (see as-user.sh).
set -e

source /scripts/lib.sh
use_shared_timezone
render_go_props ucs-agent ucs-agent
source /usr/lib/ucs-agent/scripts/envs.sh

export TMPDIR="${IDENTITY_TMP_DIR}"
cd "${IDENTITY_DATA_DIR}"
exec /scripts/as-user.sh ucs-agent \
  /data/ucs-agent \
  /data/ucs-agent/ws \
  /data/ucs-agent/tmp \
  -- /usr/sbin/ucs-agent-app --prop /usr/lib/ucs-agent/config.props
