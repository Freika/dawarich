#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Starting Rails environment: $RAILS_ENV ⚠️"

# Parse DATABASE_URL if present, otherwise use individual variables
if [ -n "$DATABASE_URL" ]; then
  # Extract components from DATABASE_URL
  DATABASE_HOST=$(echo $DATABASE_URL | awk -F[@/] '{print $4}')
  DATABASE_PORT=$(echo $DATABASE_URL | awk -F[@/:] '{print $5}')
  DATABASE_USERNAME=$(echo $DATABASE_URL | awk -F[:/@] '{print $4}')
  DATABASE_PASSWORD=$(echo $DATABASE_URL | awk -F[:/@] '{print $5}')
  DATABASE_NAME=$(echo $DATABASE_URL | awk -F[@/] '{print $5}')
else
  # Use existing environment variables
  DATABASE_HOST=${DATABASE_HOST}
  DATABASE_PORT=${DATABASE_PORT}
  DATABASE_USERNAME=${DATABASE_USERNAME}
  DATABASE_PASSWORD=${DATABASE_PASSWORD}
  DATABASE_NAME=${DATABASE_NAME}
fi

# Export main database variables to ensure they're available
export DATABASE_HOST
export DATABASE_PORT
export DATABASE_USERNAME
export DATABASE_PASSWORD
export DATABASE_NAME

# Set queue database name
QUEUE_DATABASE_NAME=${QUEUE_DATABASE_NAME:-"${DATABASE_NAME}_queue"}
export QUEUE_DATABASE_NAME
export QUEUE_DATABASE_PASSWORD
export QUEUE_DATABASE_USERNAME
export QUEUE_DATABASE_PORT
export QUEUE_DATABASE_HOST

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

# Function to check and create a PostgreSQL database
create_database() {
  local db_name=$1
  local db_password=$2

  echo "Attempting to create database $db_name if it doesn't exist..."
  PGPASSWORD=$db_password createdb -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" "$db_name" 2>/dev/null || echo "Note: Database $db_name may already exist or couldn't be created now"

  # Wait for the database to become available
  echo "⏳ Waiting for database $db_name to be ready..."
  until PGPASSWORD=$db_password psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$db_name" -c '\q' 2>/dev/null; do
    >&2 echo "Postgres database $db_name is unavailable - retrying..."
    sleep 2
  done
  echo "✅ PostgreSQL database $db_name is ready!"
}

# Set up SQLite database directory in the volume for cache and cable
SQLITE_DB_DIR="/dawarich_db_data"
mkdir -p $SQLITE_DB_DIR
echo "Created SQLite database directory at $SQLITE_DB_DIR"

# Step 1: Database Setup
echo "Setting up all required databases..."

# Create primary PostgreSQL database
create_database "$DATABASE_NAME" "$DATABASE_PASSWORD"

# Create PostgreSQL queue database for solid_queue
create_database "$QUEUE_DATABASE_NAME" "$QUEUE_DATABASE_PASSWORD"

# Setup SQLite databases for cache and cable

# Setup Cache database with SQLite
CACHE_DATABASE_PATH=${CACHE_DATABASE_PATH:-"$SQLITE_DB_DIR/${DATABASE_NAME}_cache.sqlite3"}
export CACHE_DATABASE_PATH
echo "✅ SQLite cache database configured at $CACHE_DATABASE_PATH"

# Setup Cable database with SQLite (only for production and staging)
if [ "$RAILS_ENV" = "production" ] || [ "$RAILS_ENV" = "staging" ]; then
  CABLE_DATABASE_PATH=${CABLE_DATABASE_PATH:-"$SQLITE_DB_DIR/${DATABASE_NAME}_cable.sqlite3"}
  export CABLE_DATABASE_PATH
  echo "✅ SQLite cable database configured at $CABLE_DATABASE_PATH"
fi

# Step 2: Run migrations for all databases
echo "Running migrations for all databases..."

# Run primary database migrations first (needed before other migrations)
echo "Running primary database migrations..."
bundle exec rails db:migrate

# Run PostgreSQL queue database migrations
echo "Running queue database migrations..."
bundle exec rails db:migrate:queue

# Run SQLite database migrations
echo "Running cache database migrations..."
bundle exec rails db:migrate:cache

# Run cable migrations for production/staging
if [ "$RAILS_ENV" = "production" ] || [ "$RAILS_ENV" = "staging" ]; then
  echo "Running cable database migrations..."
  bundle exec rails db:migrate:cable
fi

# Run data migrations
echo "Running DATA migrations..."
bundle exec rake data:migrate

echo "Running seeds..."
bundle exec rails db:seed

# run passed commands
bundle exec ${@}
