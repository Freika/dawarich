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

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

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
bundle exec ${@}
