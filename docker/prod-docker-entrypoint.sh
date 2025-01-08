#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "Environment: $RAILS_ENV"

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
  DATABASE_HOST=${DATABASE_HOST:-dawarich_db}
  DATABASE_PORT=${DATABASE_PORT:-5432}
  DATABASE_USERNAME=${DATABASE_USERNAME:-postgres}
  DATABASE_PASSWORD=${DATABASE_PASSWORD:-password}
  DATABASE_NAME=${DATABASE_NAME:-dawarich_production}
fi

# Function to test database connection
test_db_connection() {
  echo "Testing connection to PostgreSQL..."
  echo "Host: $DATABASE_HOST"
  echo "Port: $DATABASE_PORT"
  echo "Username: $DATABASE_USERNAME"
  echo "Database: postgres (default database)"

  if PGPASSWORD=$DATABASE_PASSWORD psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d postgres -c "SELECT 1" > /dev/null 2>&1; then
    echo "✅ Successfully connected to PostgreSQL!"
    return 0
  else
    echo "❌ Failed to connect to PostgreSQL"
    return 1
  fi
}

# Try to connect to PostgreSQL, with a timeout
max_attempts=30
attempt=1

while ! test_db_connection; do
  if [ $attempt -ge $max_attempts ]; then
    echo "Failed to connect to PostgreSQL after $max_attempts attempts. Exiting."
    exit 1
  fi

  echo "Attempt $attempt of $max_attempts. Waiting 2 seconds before retry..."
  attempt=$((attempt + 1))
  sleep 2
done

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

# Install gems
gem update --system 3.6.2
gem install bundler --version '2.5.21'

# Create the database if it doesn't exist
if PGPASSWORD=$DATABASE_PASSWORD psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -c "SELECT 1 FROM pg_database WHERE datname='$DATABASE_NAME'" | grep -q 1; then
  echo "Database $DATABASE_NAME already exists, skipping creation..."
else
  echo "Creating database $DATABASE_NAME..."
  bundle exec rails db:create
fi

# Run database migrations
echo "PostgreSQL is ready. Running database migrations..."
bundle exec rails db:migrate

# Run data migrations
echo "Running DATA migrations..."
bundle exec rake data:migrate

# Run seeds
echo "Running seeds..."
bundle exec rake db:seed

# Precompile assets
if [ "$RAILS_ENV" = "production" ]; then
  echo "Precompiling assets..."
  bundle exec rake assets:precompile
fi

# run passed commands
bundle exec ${@}
