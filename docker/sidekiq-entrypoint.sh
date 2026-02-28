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

echo "⚠️ Starting Sidekiq in $RAILS_ENV environment ⚠️"

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
