#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
: "${DATABASE_NAME:?Set an isolated build database}"
: "${REDIS_URL:?Set a private build Redis URL}"
cd "$root"
RAILS_ENV=test asdf exec bundle exec rails assets:precompile phoenix:i18n phoenix:achievements phoenix:importmap phoenix:time_zones
cd app-phoenix
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix release --overwrite
