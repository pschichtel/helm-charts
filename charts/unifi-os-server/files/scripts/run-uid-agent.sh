#!/bin/bash
# uid-agent (Go), foreground, starts as root, prepares its directories and drops to the app user (see as-user.sh).
set -e

source /scripts/lib.sh
use_shared_timezone
render_go_props uid-agent uid
source /usr/lib/uid-agent/scripts/envs.sh

export TMPDIR="${UID_AGENT_TMP_DIR}"
cd "${UID_AGENT_DATA_DIR}"
exec /scripts/as-user.sh uid \
  /data/uid \
  /data/uid/ws \
  /data/uid/ws/tmp \
  /srv/uid \
  /run/uid \
  -- /usr/sbin/uid-agent-app --props /usr/lib/uid-agent/config.props
