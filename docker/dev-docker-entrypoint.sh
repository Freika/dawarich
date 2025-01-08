#!/bin/sh

unset BUNDLE_PATH
unset BUNDLE_BIN

set -e

echo "Environment: $RAILS_ENV"

# set env var defaults
DATABASE_HOST=${DATABASE_HOST:-"dawarich_db"}
DATABASE_PORT=${DATABASE_PORT:-5432}
DATABASE_USERNAME=${DATABASE_USERNAME:-"postgres"}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-"password"}
DATABASE_NAME=${DATABASE_NAME:-"dawarich_development"}

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

# Wait for the database to be ready
until nc -zv $DATABASE_HOST ${DATABASE_PORT:-5432}; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done

# Install gems
gem update --system 3.6.2
gem install bundler --version '2.5.21'

# Create the database
if [ "$(psql "postgres://$DATABASE_USERNAME:$DATABASE_PASSWORD@$DATABASE_HOST:$DATABASE_PORT" -XtAc "SELECT 1 FROM pg_database WHERE datname='$DATABASE_NAME'")" = '1' ]; then
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

# run passed commands
bundle exec ${@}
