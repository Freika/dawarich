#!/bin/sh

set -e

. "$(dirname "$0")/entrypoint-env-guard.sh"
. "$(dirname "$0")/entrypoint-common.sh"
validate_cloud_drain_argv "$0" "$@"
validate_cloud_native_worker "$@"

bootstrap "$0" "$@"
if phoenix_lifecycle_is_native && [ "${SELF_HOSTED-true}" = false ]; then
  exec_idle_phoenix
fi
echo "⚠️ Starting Sidekiq in $RAILS_ENV environment ⚠️"
sanitize_integer_env BACKGROUND_PROCESSING_CONCURRENCY 3
wait_for_database

exec bundle exec "$@"
