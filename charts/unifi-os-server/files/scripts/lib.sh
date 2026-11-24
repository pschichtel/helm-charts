# shellcheck shell=bash
# Helpers shared by the entrypoints. Sourced; runs as root before the app
# drops privileges. Connection settings come from environment variables set by
# the chart (see templates/deployment.yaml); credentials come from Secrets.

die() { echo "$*" >&2; exit 64; }

# Core sets the time zone with ubnt-systool in its own container (rm + cp of
# /etc/localtime, then "systemctl restart cron"); the systemctl shim publishes
# the result to the shared /run/uos-tz. The other containers link to it. Until
# core has published a zone the links dangle and the apps use UTC.
use_shared_timezone() {
  ln -sfn /run/uos-tz/localtime /etc/localtime
  ln -sfn /run/uos-tz/timezone /etc/timezone
}

# The Go apps put the Postgres password into an unquoted libpq key=value DSN
# ("... password=%s dbname=%s sslmode=disable") and read their config with
# ${...} property expansion. Characters that break either are rejected here
# with a clear message instead of an obscure connection error later.
pg_check_password() {
  : "${PGPASSWORD:?PGPASSWORD is not set (postgresql.auth.<service>.existingSecret)}"
  case "$PGPASSWORD" in
    *[[:space:]\'\"\\\$]*)
      die "The Postgres password contains whitespace, quotes, a backslash or '\$'. The UniFi OS Go services cannot use such passwords; choose another one." ;;
  esac
}

# The Go services' schema migrations contain "OWNER TO <role>" for a fixed
# role name; logging in as another user fails with 'role "..." does not exist'
# on the first migration and leaves the database marked dirty.
pg_check_user() {
  if [ -n "${PG_REQUIRED_USER:-}" ] && [ "${PGUSER:-}" != "$PG_REQUIRED_USER" ]; then
    die "This service must connect to Postgres as user '$PG_REQUIRED_USER' (its schema migrations assign ownership to that role), but the secret provides '${PGUSER:-}'."
  fi
}

wait_for_postgres() {
  : "${PGHOST:?PGHOST is not set (postgresql.host)}"
  local _
  for _ in $(seq 1 90); do
    pg_isready -q -h "$PGHOST" -p "${PGPORT:-5432}" && return 0
    sleep 2
  done
  echo "Postgres at $PGHOST:${PGPORT:-5432} is not reachable; starting anyway" >&2
}

# render_go_props <app> <owner> [nodb]
# Writes /etc/<app>/config.props, which every Go service loads through the
# `overrides` list of its stock config.props: the chart's static settings from
# /config/<app>.props plus the database settings from the environment.
render_go_props() {
  local app=$1 owner=$2 nodb=${3:-} dst=/etc/$1/config.props
  mkdir -p "/etc/$app"
  {
    cat "/config/$app.props"
    if [ "$nodb" != nodb ]; then
      pg_check_password
      pg_check_user
      printf '\n# --- generated at container start from the chart values and secret\n'
      printf 'db.host = %s\ndb.port = %s\ndb.username = %s\ndb.password = %s\n' \
        "$PGHOST" "${PGPORT:-5432}" "${PGUSER:?PGUSER is not set}" "$PGPASSWORD"
      [ -z "${DB_NAME:-}" ] || printf 'db.name = %s\n' "$DB_NAME"
      [ -z "${DB_SYSLOG_NAME:-}" ] || printf 'db.systemlog.name = %s\n' "$DB_SYSLOG_NAME"
    fi
  } > "$dst"
  chown "$owner:" "$dst"
  chmod 600 "$dst"
}
