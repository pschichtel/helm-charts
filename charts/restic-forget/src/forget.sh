#!/usr/bin/env sh

set -eu

restic unlock
restic --no-cache --retry-lock "${RETRY_LOCK_TIMEOUT:-0}" forget "$@" --prune