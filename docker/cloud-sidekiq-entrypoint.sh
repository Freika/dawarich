#!/bin/sh

set -e

. "$(dirname "$0")/entrypoint-env-guard.sh"
. "$(dirname "$0")/entrypoint-common.sh"

bootstrap "$0" "$@"
echo "⚠️ Starting Sidekiq in $RAILS_ENV environment ⚠️"
sanitize_integer_env BACKGROUND_PROCESSING_CONCURRENCY 3
wait_for_database

exec bundle exec "$@"
