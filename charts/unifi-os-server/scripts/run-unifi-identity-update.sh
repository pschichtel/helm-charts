#!/bin/bash
# unifi-identity-update (Go), foreground, starts as root, prepares its directories and drops to the app user (see as-user.sh).
set -e

/scripts/netbridge.sh
source /usr/lib/unifi-identity-update/scripts/envs.sh

export TMPDIR="${IDENTITY_TMP_DIR}"
cd "${IDENTITY_DATA_DIR}"
exec /scripts/as-user.sh ucs-update \
  /data/unifi-identity-update \
  /data/unifi-identity-update/ws \
  /data/unifi-identity-update/tmp \
  -- /usr/sbin/unifi-identity-update-app --prop /usr/lib/unifi-identity-update/config.props
