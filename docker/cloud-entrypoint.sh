#!/bin/sh

set -e

. "$(dirname "$0")/entrypoint-env-guard.sh"
. "$(dirname "$0")/entrypoint-common.sh"

bootstrap "$0" "$@"
echo "⚠️ Starting Rails environment: $RAILS_ENV ⚠️"
sanitize_integer_env WEB_CONCURRENCY 1
wait_for_database

rm -f "$APP_PATH/tmp/pids/server.pid"

if is_server_command "$@"; then
  ready=0
  dawarich eval 'Dawarich.Release.halt_unless_ready()' || ready=$?
  if [ "$ready" -eq 0 ]; then
    exec_under_phoenix "$@"
  fi
  case "$ready" in
    3) cause="Phoenix schemas are missing, unreadable or behind this image" ;;
    4) cause="the Erlang cookie file cannot be read" ;;
    5) cause="PostgreSQL did not answer the Phoenix readiness check" ;;
    *) cause="the Phoenix readiness check failed with exit status $ready" ;;
  esac
  echo "$cause; starting Rails without the Phoenix supervisor" >&2
fi

exec bundle exec "$@"
