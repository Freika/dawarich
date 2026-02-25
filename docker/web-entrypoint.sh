#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Starting Rails environment: $RAILS_ENV ⚠️"

# Parse DATABASE_URL if present, otherwise use individual variables
if [ -n "$DATABASE_URL" ]; then
  # Extract components from DATABASE_URL
  DATABASE_HOST="$(echo "$DATABASE_URL" | awk -F[@/] '{print $4}')"
  DATABASE_PORT="$(echo "$DATABASE_URL" | awk -F[@/:] '{print $5}')"
  DATABASE_USERNAME="$(echo "$DATABASE_URL" | awk -F[:/@] '{print $4}')"
  DATABASE_PASSWORD="$(echo "$DATABASE_URL" | awk -F[:/@] '{print $5}')"
  DATABASE_NAME="$(echo "$DATABASE_URL" | awk -F[@/] '{print $5}')"
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
if [ -d "/tmp/public_assets" ]; then
  echo "📦 Syncing static assets to public volume..."
  # Remove old compiled assets to prevent stale files from persisting
  rm -rf $APP_PATH/public/assets
  cp -r /tmp/public_assets/* $APP_PATH/public/
  echo "✅ Static assets synced!"
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

# Optionally start prometheus exporter alongside the web process
PROMETHEUS_EXPORTER_PID=""
if [ "$PROMETHEUS_EXPORTER_ENABLED" = "true" ]; then
  PROM_HOST=${PROMETHEUS_EXPORTER_HOST:-0.0.0.0}
  PROM_PORT=${PROMETHEUS_EXPORTER_PORT:-9394}

  case "$PROM_HOST" in
    ""|"0.0.0.0"|"::"|"127.0.0.1"|"localhost"|"ANY")
      echo "📈 Starting Prometheus exporter on ${PROM_HOST:-0.0.0.0}:${PROM_PORT}..."
      bundle exec prometheus_exporter -b "${PROM_HOST:-ANY}" -p "${PROM_PORT}" &
      PROMETHEUS_EXPORTER_PID=$!

      cleanup() {
        if [ -n "$PROMETHEUS_EXPORTER_PID" ] && kill -0 "$PROMETHEUS_EXPORTER_PID" 2>/dev/null; then
          echo "🛑 Stopping Prometheus exporter (PID $PROMETHEUS_EXPORTER_PID)..."
          kill "$PROMETHEUS_EXPORTER_PID"
          wait "$PROMETHEUS_EXPORTER_PID" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT INT TERM
      ;;
    *)
      echo "ℹ️ PROMETHEUS_EXPORTER_HOST is set to $PROM_HOST, skipping embedded exporter startup."
      ;;
  esac
fi

# run passed commands
exec bundle exec ${@}
