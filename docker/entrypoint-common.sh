#!/bin/sh

bootstrap() {
  unset BUNDLE_PATH BUNDLE_BIN
  if [ "$(id -u)" = 0 ]; then
    drop_privileges "${PUID:-32767}" "${PGID:-32767}" "$@"
  fi
  require_rails_env
}

require_rails_env() {
  case "${RAILS_ENV:-}" in
    '' | development)
      echo "RAILS_ENV is '${RAILS_ENV:-}'; set RAILS_ENV=production before starting a Cloud process" >&2
      exit 1
      ;;
  esac
}

drop_privileges() {
  _uid="$1"
  _gid="$2"
  shift 2
  case "$_uid" in
    '' | *[!0-9]* | 0*)
      echo "Refusing to drop privileges to uid '$_uid': PUID must be a numeric uid other than 0" >&2
      exit 1
      ;;
  esac
  for _path in "$APP_PATH/tmp" "$APP_PATH/storage"; do
    [ -d "$_path" ] || continue
    if [ "$(ls -nd "$_path" | awk '{print $3}')" != "$_uid" ]; then
      echo "🔑 Adjusting ownership of $_path to $_uid:$_gid..."
      chown -R "$_uid:$_gid" "$_path"
    fi
  done
  exec gosu "$_uid:$_gid" env HOME="$APP_PATH/tmp" "$@"
}

wait_for_database() {
  _max="${1:-0}"
  if [ -n "${DATABASE_URL:-}" ]; then
    set -- "$(printf '%s' "$DATABASE_URL" | sed 's#^postgis://#postgres://#')"
  else
    set -- -h "$DATABASE_HOST" -p "${DATABASE_PORT:-5432}" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME"
  fi

  _tries=1
  until PGCONNECT_TIMEOUT=5 PGPASSWORD="${DATABASE_PASSWORD:-}" psql "$@" -c 'SELECT 1' >/dev/null 2>&1; do
    if [ "$_max" -gt 0 ] && [ "$_tries" -ge "$_max" ]; then
      echo "PostgreSQL is still unavailable after $_max attempts:" >&2
      PGCONNECT_TIMEOUT=5 PGPASSWORD="${DATABASE_PASSWORD:-}" psql "$@" -c 'SELECT 1' >/dev/null
      return
    fi
    _tries=$((_tries + 1))
    echo "PostgreSQL is unavailable - retrying..." >&2
    sleep 2
  done
  unset _max _tries
}

is_server_command() {
  case "$1 $2" in
    "bin/rails server" | "bin/rails s" | "rails server" | "rails s" | puma*) return 0 ;;
  esac
  return 1
}

exec_under_phoenix() {
  DAWARICH_RAILS_ARGS="$(printf '%s\037' bundle exec "$@")"
  export DAWARICH_RAILS_ARGS
  exec dawarich start
}
