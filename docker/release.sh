#!/bin/sh

set -e

. "$(dirname "$0")/entrypoint-env-guard.sh"
. "$(dirname "$0")/entrypoint-common.sh"
validate_phoenix_lifecycle

bootstrap "$0" "$@"
wait_for_database 60

if phoenix_lifecycle_is_native; then
  dawarich migrate
  dawarich seeds
  exit 0
fi

echo "Running schema migrations..."
bundle exec rails db:migrate

echo "Running Phoenix migrations..."
if ! dawarich eval 'Dawarich.Release.migrate()'; then
  if env_value_is_truthy "${SELF_HOSTED-true}"; then
    echo "Phoenix migrations failed; web containers will start Rails without the Phoenix supervisor" >&2
  else
    echo "Phoenix migrations failed; the deploy stops here and the running containers stay" >&2
    exit 1
  fi
fi
