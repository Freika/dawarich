#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "⚠️ Environment: $RAILS_ENV ⚠️"

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
