#!/usr/bin/env sh

set -eu

restic --no-cache --retry-lock "${RETRY_LOCK_TIMEOUT:-0}" forget "$@" --prune