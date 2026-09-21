#!/bin/sh

# Shared helpers for the Cloud entrypoints. web-entrypoint.sh and
# sidekiq-entrypoint.sh keep their own copies for now.

parse_database_url() {
  if [ -n "$DATABASE_URL" ]; then
    _db_url_stripped="${DATABASE_URL#*://}"
    _db_credentials="${_db_url_stripped%%@*}"
    _db_host_path="${_db_url_stripped#*@}"
    DATABASE_USERNAME="${_db_credentials%%:*}"
    DATABASE_PASSWORD="${_db_credentials#*:}"
    _db_host_port="${_db_host_path%%/*}"
    DATABASE_NAME="${_db_host_path#*/}"
    DATABASE_HOST="${_db_host_port%%:*}"
    if [ "$_db_host_port" != "$DATABASE_HOST" ]; then
      DATABASE_PORT="${_db_host_port#*:}"
    else
      DATABASE_PORT="5432"
    fi
    unset _db_url_stripped _db_credentials _db_host_path _db_host_port
  fi

  export DATABASE_HOST DATABASE_PORT DATABASE_USERNAME DATABASE_PASSWORD DATABASE_NAME
}

wait_for_database() {
  echo "⏳ Waiting for $DATABASE_HOST:$DATABASE_PORT/$DATABASE_NAME..."
  until PGPASSWORD="$DATABASE_PASSWORD" psql \
    -h "$DATABASE_HOST" -p "$DATABASE_PORT" \
    -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c '\q' 2>/dev/null; do
    >&2 echo "Postgres is unavailable - retrying..."
    sleep 2
  done
  echo "✅ PostgreSQL is ready!"
}
