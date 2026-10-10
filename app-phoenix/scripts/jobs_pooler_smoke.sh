#!/bin/sh
set -eu

case "${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)}" in
  unix://*) ;;
  *) echo "jobs pooler smoke: the Docker engine is not local" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
run="a1-pooler-$$"
work="$(mktemp -d)"
database="${PHOENIX_TEST_DATABASE:-a1_pooler}"
image="${POOLER_IMAGE:-a1-pgbouncer:local}"

cleanup() {
  docker rm -fv "$run-db" "$run-bouncer" >/dev/null 2>&1 || true
  docker network rm "$run" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

docker network create "$run" >/dev/null
docker run -d --platform "${POSTGIS_PLATFORM:-linux/amd64}" --name "$run-db" --network "$run" -e POSTGRES_PASSWORD=postgres \
  "${POSTGIS_IMAGE:-postgis/postgis:17-3.5-alpine}" -c timezone=Europe/Berlin >/dev/null

cat >"$work/pgbouncer.ini" <<INI
[databases]
* = host=$run-db port=5432
[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
unix_socket_dir =
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 40
max_client_conn = 200
max_prepared_statements = 200
INI
echo '"postgres" "postgres"' >"$work/userlist.txt"
cat >"$work/Dockerfile" <<'DOCKERFILE'
FROM debian:trixie-slim
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg postgresql-common \
 && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends pgbouncer \
 && rm -rf /var/lib/apt/lists/*
USER postgres
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
DOCKERFILE
if ! docker image inspect "$image" >/dev/null 2>&1; then
  df -h /System/Volumes/Data
  [ "$(df -k /System/Volumes/Data | awk 'NR==2 {print $4}')" -ge 15728640 ] || {
    echo "jobs pooler smoke: disk below 15 GiB" >&2; exit 2;
  }
  build_rc=0
  docker build -q -t "$image" "$work" >/dev/null || build_rc=$?
  docker builder prune -af >/dev/null
  [ "$build_rc" -eq 0 ] || exit "$build_rc"
fi
docker run -d --name "$run-bouncer" --network "$run" \
  -v "$work/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro" \
  -v "$work/userlist.txt:/etc/pgbouncer/userlist.txt:ro" \
  -p "127.0.0.1:${POOLER_PORT:-}:6432" "$image" >/dev/null
port="$(docker port "$run-bouncer" 6432/tcp | head -1 | sed 's/.*://')"

tries=0
until docker exec "$run-db" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || { echo "jobs pooler smoke: PostgreSQL did not start" >&2; exit 1; }
  sleep 1
done

docker exec "$run-bouncer" pgbouncer --version | head -1
docker exec "$run-db" psql -U postgres -tAc 'SHOW TimeZone'
docker exec "$run-db" createdb -U postgres "$database"
docker exec -i "$run-db" psql -q -X -v ON_ERROR_STOP=1 -U postgres -d "$database" \
  <"$root/priv/release_migrations/baseline.sql" >/dev/null

cd "$root"
[ "$#" -gt 0 ] || set -- test/dawarich/jobs test/dawarich/trips test/dawarich/mail test/dawarich/app_version test/dawarich/ruby_float_test.exs
env PATH="$HOME/.asdf/shims:$PATH" LANG=en_US.UTF-8 MIX_ENV=test PHOENIX_TEST_DATABASE="$database" \
  DATABASE_HOST=127.0.0.1 DATABASE_PORT="$port" DATABASE_USERNAME=postgres DATABASE_PASSWORD=postgres \
  mix test "$@"
echo "jobs pooler smoke: ok"
