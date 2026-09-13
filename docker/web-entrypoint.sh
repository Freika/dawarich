#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

load_env_from_files() {
  # Iterate over all env var names that end with _FILE
  # POSIX note: use env | awk to collect variable names reliably.
  for VAR_NAME in $(env | awk -F= '/_FILE=/{print $1}'); do
    BASE_NAME="${VAR_NAME%_FILE}"

    # Expand current values of BASE_NAME and VAR_NAME (POSIX-friendly; no ${!var})
    eval "BASE_VAL=\"\${${BASE_NAME}:-}\""
    eval "FILE_PATH=\"\${${VAR_NAME}:-}\""

    # If both are provided, fail fast to avoid ambiguity
    if [ -n "$BASE_VAL" ] && [ -n "$FILE_PATH" ]; then
      echo "❌ Both $BASE_NAME and ${BASE_NAME}_FILE are set; please set only one." >&2
      exit 1
    fi

    # If *_FILE is provided, read file content and export into BASE_NAME
    if [ -n "$FILE_PATH" ]; then
      if [ ! -r "$FILE_PATH" ]; then
        echo "❌ ${BASE_NAME}_FILE points to an unreadable file: $FILE_PATH" >&2
        exit 1
      fi

      # Read file; command substitution strips trailing newline.
      VAL=$(cat "$FILE_PATH")

      echo "🔐 Read secret for $BASE_NAME from $FILE_PATH; exporting $BASE_NAME"

      export "$BASE_NAME=$VAL"
      unset "$VAR_NAME"
    fi
  done
}

# Run before anything else uses env vars
load_env_from_files

echo "⚠️ Starting Rails environment: $RAILS_ENV ⚠️"

. "$(dirname "$0")/entrypoint-env-guard.sh"
sanitize_integer_env WEB_CONCURRENCY 1

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

# Export main database variables to ensure they're available
export DATABASE_HOST
export DATABASE_PORT
export DATABASE_USERNAME
export DATABASE_PASSWORD
export DATABASE_NAME

# Remove pre-existing puma/passenger server.pid
rm -f "$APP_PATH/tmp/pids/server.pid"

# Sync static assets from image to volume
# This ensures new and updated files are copied to the persistent volume
ASSETS_DIST="$APP_PATH/public_dist"
if [ -d "$ASSETS_DIST" ]; then
  echo "📦 Syncing static assets to public volume..."
  # Remove old compiled assets to prevent stale files from persisting
  rm -rf $APP_PATH/public/assets
  cp -r "$ASSETS_DIST"/* $APP_PATH/public/
  echo "✅ Static assets synced!"
else
  echo "⚠️ $ASSETS_DIST not found — static assets were NOT synced. The public volume may keep serving assets from a previous version."
fi

# Function to check and create a PostgreSQL database
create_database() {
  local db_name=$1
  local db_password=$2
  local db_host=$3
  local db_port=$4
  local db_username=$5

  echo "Attempting to create database $db_name if it doesn't exist..."
  PGPASSWORD=$db_password createdb -h "$db_host" -p "$db_port" -U "$db_username" "$db_name" 2>/dev/null || echo "Note: Database $db_name may already exist or couldn't be created now"

  # Wait for the database to become available
  echo "⏳ Waiting for database $db_name to be ready..."
  until PGPASSWORD=$db_password psql -h "$db_host" -p "$db_port" -U "$db_username" -d "$db_name" -c '\q' 2>/dev/null; do
    >&2 echo "Postgres database $db_name is unavailable - retrying..."
    sleep 2
  done
  echo "✅ PostgreSQL database $db_name is ready!"
}

# Step 1: Database Setup
echo "Setting up all required databases..."

# Create primary PostgreSQL database
create_database "$DATABASE_NAME" "$DATABASE_PASSWORD" "$DATABASE_HOST" "$DATABASE_PORT" "$DATABASE_USERNAME"

# Step 2: Run migrations for all databases
echo "Running migrations for all databases..."

# Run primary database migrations first (needed before other migrations)
echo "Running primary database migrations..."
bundle exec rails db:migrate

# Run data migrations
echo "Running DATA migrations..."
bundle exec rake data:migrate

echo "Running seeds..."
bundle exec rails db:seed

# run passed commands
exec bundle exec "${@}"
