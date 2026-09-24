#!/bin/sh

# Cloud Sidekiq entrypoint. Separate from sidekiq-entrypoint.sh, which must
# swallow the positional `sidekiq` compose passes; Cloud needs "$@" honoured.

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Starting Sidekiq in $RAILS_ENV environment ⚠️"

. /usr/local/bin/entrypoint-env-guard.sh
sanitize_integer_env BACKGROUND_PROCESSING_CONCURRENCY 3

. /usr/local/bin/entrypoint-common.sh

parse_database_url
wait_for_database

exec bundle exec "${@}"
