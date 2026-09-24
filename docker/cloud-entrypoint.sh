#!/bin/sh

# Cloud web entrypoint. No createdb, no migrate, no seed — schema changes run
# once per deploy via release.sh. Self-hosted uses web-entrypoint.sh.

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Starting Rails environment: $RAILS_ENV ⚠️"

. /usr/local/bin/entrypoint-env-guard.sh
sanitize_integer_env WEB_CONCURRENCY 1

. /usr/local/bin/entrypoint-common.sh

parse_database_url
wait_for_database

rm -f "$APP_PATH/tmp/pids/server.pid"

exec bundle exec "${@}"
