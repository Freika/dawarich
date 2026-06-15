#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Starting Sidekiq in $RAILS_ENV environment ⚠️"

# Optional privilege drop. When PUID/PGID are set and the container starts as
# root, fix ownership of the mounted writable paths, then re-exec as that user.
# Prefer this over compose `user:`, which starts unprivileged and cannot chown
# root-owned volumes.
if [ "$(id -u)" = "0" ] && [ -n "${PUID}${PGID}" ]; then
  TARGET_UID="${PUID:-1000}"
  TARGET_GID="${PGID:-1000}"
  for _dir in public storage tmp db log; do
    _path="$APP_PATH/$_dir"
    [ -d "$_path" ] || continue
    if [ "$(stat -c '%u' "$_path")" != "$TARGET_UID" ]; then
      echo "🔑 Adjusting ownership of $_path to $TARGET_UID:$TARGET_GID..."
      chown -R "$TARGET_UID:$TARGET_GID" "$_path"
    fi
  done
  exec gosu "$TARGET_UID:$TARGET_GID" "$0" "$@"
fi

# Parse DATABASE_URL if present, otherwise use individual variables
if [ -n "$DATABASE_URL" ]; then
  # Strip scheme (postgres:// or postgresql://)
  _db_url_stripped="${DATABASE_URL#*://}"
  # Split at '@' -> credentials @ host_path
  _db_credentials="${_db_url_stripped%%@*}"
  _db_host_path="${_db_url_stripped#*@}"
  # Extract username and password from credentials
  DATABASE_USERNAME="${_db_credentials%%:*}"
  DATABASE_PASSWORD="${_db_credentials#*:}"
  # Extract host_port and dbname from host_path
  _db_host_port="${_db_host_path%%/*}"
  DATABASE_NAME="${_db_host_path#*/}"
  # Split host and port (port may be absent)
  DATABASE_HOST="${_db_host_port%%:*}"
  if [ "$_db_host_port" != "$DATABASE_HOST" ]; then
    DATABASE_PORT="${_db_host_port#*:}"
  else
    DATABASE_PORT="5432"
  fi
fi

# Wait for the database to become available
echo "⏳ Waiting for database to be ready..."
until PGPASSWORD=$DATABASE_PASSWORD psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c '\q'; do
  >&2 echo "Postgres is unavailable - retrying..."
  sleep 2
done
echo "✅ PostgreSQL is ready!"

# run sidekiq
exec bundle exec sidekiq
