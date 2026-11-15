#!/bin/bash
# unifi-directory (Go), foreground, starts as root, prepares its directories and drops to the app user (see as-user.sh).
set -e

source /usr/lib/unifi-directory/scripts/envs.sh

export TMPDIR="${DIRECTORY_TMP_DIR}"
cd "${DIRECTORY_DATA_DIR}"
exec /scripts/as-user.sh unifi-directory \
  /data/unifi-directory \
  /data/unifi-directory/ws \
  /data/unifi-directory/tmp \
  -- /usr/sbin/unifi-directory-app --prop /usr/lib/unifi-directory/config.props
