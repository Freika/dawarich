#!/bin/sh

set -e

echo "Environment: $RAILS_ENV"

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/server.pid

# Wait for the database to be ready
until nc -zv wardu_db 5432; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done

# Create the database
echo "Creating database $DATABASE_NAME..."
bundle exec rails db:create

# Run database migrations
echo "PostgreSQL is ready. Running database migrations..."
bundle exec rails db:prepare

# run passed commands
bundle exec ${@}
