#!/bin/sh

set -e

. "$(dirname "$0")/entrypoint-common.sh"

bootstrap "$0" "$@"
wait_for_database 60

echo "Running schema migrations..."
bundle exec rails db:migrate

echo "Running Phoenix migrations..."
if ! dawarich eval 'Dawarich.Release.migrate()'; then
  echo "Phoenix migrations failed; web containers will start Rails without the Phoenix supervisor" >&2
fi
