#!/bin/bash
set -euo pipefail
[ "${RAILS_ENV:-}" = test ] && [ -n "${DATABASE_NAME:-}" ] && [ -n "${REDIS_URL:-}" ] || exit 64
RAILS_ENV=test DATABASE_NAME="$DATABASE_NAME" REDIS_URL="$REDIS_URL" bundle config set --local without development
RAILS_ENV=test DATABASE_NAME="$DATABASE_NAME" REDIS_URL="$REDIS_URL" bundle install --jobs 2 --retry 3
RAILS_ENV=test DATABASE_NAME="$DATABASE_NAME" REDIS_URL="$REDIS_URL" exec bundle exec rails server -b 0.0.0.0 -p 3000
