#!/bin/sh
set -eu
case "${1:-up}" in
  up)
    docker network inspect schema-parity >/dev/null 2>&1 || docker network create schema-parity >/dev/null
    docker inspect sp-db >/dev/null 2>&1 || docker run -d --rm --name sp-db --network schema-parity \
      -p 127.0.0.1:55532:5432 -e POSTGRES_PASSWORD=parity \
      postgis/postgis:17-3.5@sha256:01a6a70e41e6c4467c8f55f6063555ed72db2d6662cd0d571040d42eadaeb6f6 >/dev/null
    docker inspect sp-redis >/dev/null 2>&1 || docker run -d --rm --name sp-redis --network schema-parity \
      -p 127.0.0.1:56479:6379 redis:7.4-alpine >/dev/null
    waited=0
    until docker exec sp-db pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do
      waited=$((waited + 1))
      if [ "$waited" -ge 120 ]; then
        echo "sp-db did not accept connections within 120 s" >&2
        exit 1
      fi
      sleep 1
    done
    docker exec sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET fsync = off" \
      -c "ALTER SYSTEM SET full_page_writes = off" -c "ALTER SYSTEM SET synchronous_commit = off" \
      -c "SELECT pg_reload_conf()" >/dev/null
    ;;
  down)
    docker rm -f sp-db sp-redis >/dev/null 2>&1 || true
    docker network rm schema-parity >/dev/null 2>&1 || true
    ;;
esac
