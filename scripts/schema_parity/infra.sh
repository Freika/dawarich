#!/bin/sh
set -eu
case "${1:-up}" in
  up)
    docker network inspect schema-parity >/dev/null 2>&1 || docker network create schema-parity >/dev/null
    docker inspect sp-db >/dev/null 2>&1 || docker run -d --rm --name sp-db --network schema-parity \
      -p 127.0.0.1:55532:5432 -e POSTGRES_PASSWORD=parity postgis/postgis:17-3.5 >/dev/null
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
    ;;
  down)
    docker rm -f sp-db sp-redis >/dev/null 2>&1 || true
    docker network rm schema-parity >/dev/null 2>&1 || true
    ;;
esac
