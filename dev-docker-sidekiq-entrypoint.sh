#!/bin/sh

set -e

echo "Environment: $RAILS_ENV"

# Wait for the database to be ready
until nc -zv $DATABASE_HOST 5432; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done

# run passed commands
bundle exec ${@}
