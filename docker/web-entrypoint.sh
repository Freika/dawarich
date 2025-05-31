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

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

# Function to check and create a database
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

# Create and check primary database
create_database "$DATABASE_NAME" "$DATABASE_PASSWORD"

# Handle additional databases based on environment
if [ "$RAILS_ENV" = "development" ] || [ "$RAILS_ENV" = "production" ] || [ "$RAILS_ENV" = "staging" ]; then
  # Setup Queue database
  QUEUE_DATABASE_NAME=${QUEUE_DATABASE_NAME:-${DATABASE_NAME}_queue}
  QUEUE_DATABASE_PASSWORD=${QUEUE_DATABASE_PASSWORD:-$DATABASE_PASSWORD}
  create_database "$QUEUE_DATABASE_NAME" "$QUEUE_DATABASE_PASSWORD"

  # Setup Cache database
  CACHE_DATABASE_NAME=${CACHE_DATABASE_NAME:-${DATABASE_NAME}_cache}
  CACHE_DATABASE_PASSWORD=${CACHE_DATABASE_PASSWORD:-$DATABASE_PASSWORD}
  create_database "$CACHE_DATABASE_NAME" "$CACHE_DATABASE_PASSWORD"
fi

# Setup Cable database (only for production and staging)
if [ "$RAILS_ENV" = "production" ] || [ "$RAILS_ENV" = "staging" ]; then
  CABLE_DATABASE_NAME=${CABLE_DATABASE_NAME:-${DATABASE_NAME}_cable}
  CABLE_DATABASE_PASSWORD=${CABLE_DATABASE_PASSWORD:-$DATABASE_PASSWORD}
  create_database "$CABLE_DATABASE_NAME" "$CABLE_DATABASE_PASSWORD"
fi

# Run database migrations
echo "PostgreSQL is ready. Running database migrations..."
bundle exec rails db:migrate

# Run data migrations
echo "Running DATA migrations..."
bundle exec rake data:migrate

# if [ "$RAILS_ENV" != "production" ]; then
  echo "Running seeds..."
  bundle exec rails db:seed
# fi

# run passed commands
bundle exec ${@}
