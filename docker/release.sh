#!/bin/sh

# One-shot Cloud release step, run once per deploy before containers take
# traffic. Schema migrations only: `rake data:migrate` stays manual because
# several data migrations are heavy recalculations.

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

. /usr/local/bin/entrypoint-common.sh

parse_database_url
wait_for_database

echo "🚚 Running schema migrations..."
bundle exec rails db:migrate
echo "✅ Migrations complete."
