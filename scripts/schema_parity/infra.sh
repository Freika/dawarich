#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
case "$pg_major" in
  14) image=postgis/postgis:14-3.5@sha256:2543ae2bc9497ca62cd740268be228f7a6974020207634e2b189fe36be82b749 ;;
  17) image=postgis/postgis:17-3.5@sha256:01a6a70e41e6c4467c8f55f6063555ed72db2d6662cd0d571040d42eadaeb6f6 ;;
esac
publishes() {
  published="$(docker port "$1" "$2" 2>&1)" || true
  [ "$published" = "127.0.0.1:$3" ] || { echo "$1 publishes '$published' for $2, not 127.0.0.1:$3" >&2; exit 1; }
}
case "${1:-up}" in
  up)
    docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null
    docker inspect "$db_container" >/dev/null 2>&1 || docker run -d --rm --name "$db_container" --network "$network" \
      -p "127.0.0.1:$db_port:5432" -e POSTGRES_PASSWORD=parity "$image" >/dev/null
    docker inspect "$redis_container" >/dev/null 2>&1 || docker run -d --rm --name "$redis_container" --network "$network" \
      -p "127.0.0.1:$redis_port:6379" redis:7.4-alpine >/dev/null
    publishes "$db_container" 5432 "$db_port"
    publishes "$redis_container" 6379 "$redis_port"
    waited=0
    until docker exec "$db_container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do
      waited=$((waited + 1))
      if [ "$waited" -ge 120 ]; then
        echo "$db_container did not accept connections within 120 s" >&2
        exit 1
      fi
      sleep 1
    done
    mismatch="$(check_server_major)" || { echo "$mismatch" >&2; exit 1; }
    docker exec "$db_container" psql -U postgres -q -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET fsync = off" \
      -c "ALTER SYSTEM SET full_page_writes = off" -c "ALTER SYSTEM SET synchronous_commit = off" \
      -c "SELECT pg_reload_conf()" >/dev/null
    ;;
  down)
    docker rm -f "$db_container" "$redis_container" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    ;;
esac
