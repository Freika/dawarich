#!/bin/sh

set -e

echo "Environment: $RAILS_ENV"

# set env var defaults
DATABASE_HOST=${DATABASE_HOST:-"dawarich_db"}
DATABASE_PORT=${DATABASE_PORT:-5432}
DATABASE_USER=${DATABASE_USER:-"postgres"}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-"password"}
DATABASE_NAME=${DATABASE_NAME:-"dawarich_development"}

# Wait for the database to be ready
until nc -zv $DATABASE_HOST ${DATABASE_PORT:-5432}; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done

# run passed commands
bundle exec ${@}
