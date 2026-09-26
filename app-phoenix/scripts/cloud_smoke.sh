#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

IMAGE="${IMAGE:-dawarich:a0c-local}"
WAIT="${SMOKE_WAIT_SECONDS:-300}"
net=a0c-cloud
run="a0c-smoke=$$"

fail() {
  echo "$1" >&2
  exit 1
}

case "${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)}" in
  unix://*) ;;
  *) fail "the Docker engine is not local; never run this against a remote engine such as dawarich-swarm" ;;
esac
if docker ps -a --format '{{.Names}}' | grep -q '^a0c_'; then
  fail "a0c_* containers already exist; remove them first"
fi
port=0
curl -s -m 5 -o /dev/null http://127.0.0.1:3901/ || port=$?
[ "$port" = 7 ] || fail "port 3901 is in use"

work="$(mktemp -d)"
cleanup() {
  ec=$?
  if [ "$ec" -ne 0 ]; then
    for c in a0c_bouncer a0c_probe a0c_web a0c_worker; do
      docker logs --tail 40 "$c" 2>&1 | sed "s/^/[$c] /" >&2 || true
    done
  fi
  docker rm -f $(docker ps -aq --filter "label=$run") >/dev/null 2>&1 || true
  docker network rm $(docker network ls -q --filter "label=$run") >/dev/null 2>&1 || true
  docker rmi -f a0c-pgbouncer:local >/dev/null 2>&1 || true
  rm -rf "$work"
  exit "$ec"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

procfile() {
  sed -n "s/^$1: //p" Procfile.cloud
}

sql() {
  docker exec a0c_db psql -U postgres -d dawarich_cloud -Atc "$1"
}

app() {
  docker run --init --label "$run" --network "$net" --env-file "$work/env" "$@"
}

proc_user() {
  docker exec "$1" sh -c "ps -o user= -p \"\$(pgrep -o -f '$2')\"" | tr -d ' '
}

under_beam() {
  docker exec "$1" sh -c 'p=$(pgrep -o -f "^puma [0-9]"); while [ -n "$p" ] && [ "$p" -gt 1 ]; do [ "$(ps -o comm= -p "$p")" = beam.smp ] && exit 0; p=$(ps -o ppid= -p "$p" | tr -d " "); done; exit 1'
}

wait_until() {
  tries=0
  until eval "$1"; do
    tries=$((tries + 1))
    [ "$tries" -lt "$WAIT" ] || fail "$2"
    sleep 1
  done
}

healthy='curl -fsS -m 5 http://127.0.0.1:3901/api/v1/health 2>/dev/null | grep -q "\"status\""'

docker network create --label "$run" "$net" >/dev/null
docker run -d --name a0c_db --label "$run" --network "$net" -e POSTGRES_PASSWORD=postgres postgis/postgis:17-3.5-alpine >/dev/null
docker run -d --name a0c_redis --label "$run" --network "$net" redis:7.4-alpine >/dev/null

mkdir "$work/bouncer"
cat >"$work/bouncer/pgbouncer.ini" <<'EOF'
[databases]
dawarich_cloud = host=a0c_db port=5432 dbname=dawarich_cloud

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
unix_socket_dir =
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
server_round_robin = 1
default_pool_size = 4
min_pool_size = 2
max_prepared_statements = 200
EOF
echo '"dawarich_cloud" "cloud"' >"$work/bouncer/userlist.txt"
cat >"$work/bouncer/Dockerfile" <<'EOF'
FROM debian:trixie-slim
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends pgbouncer \
    && rm -rf /var/lib/apt/lists/*
COPY pgbouncer.ini userlist.txt /etc/pgbouncer/
USER nobody
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
EOF
docker build -q -t a0c-pgbouncer:local "$work/bouncer" >/dev/null
docker run -d --name a0c_bouncer --label "$run" --network "$net" a0c-pgbouncer:local >/dev/null

wait_until '[ "$(docker logs a0c_db 2>&1 | grep -c "ready to accept connections")" -ge 2 ]' "database did not start"
docker exec -i a0c_db psql -v ON_ERROR_STOP=1 -q -U postgres <<'EOF'
CREATE ROLE dawarich_cloud LOGIN PASSWORD 'cloud';
CREATE DATABASE dawarich_cloud;
\c dawarich_cloud
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
GRANT USAGE, CREATE ON SCHEMA public TO dawarich_cloud;
EOF

cat >"$work/env" <<EOF
RAILS_ENV=production
PORT=3000
DATABASE_HOST=a0c_bouncer
DATABASE_PORT=6432
DATABASE_USERNAME=dawarich_cloud
DATABASE_PASSWORD=cloud
DATABASE_NAME=dawarich_cloud
DATABASE_ADVISORY_LOCKS=false
REDIS_URL=redis://a0c_redis:6379
SECRET_KEY_BASE=$(od -An -N64 -tx1 /dev/urandom | tr -d ' \n')
APPLICATION_HOSTS=localhost,127.0.0.1
WEB_CONCURRENCY=1
EOF
sed -e 's/^DATABASE_HOST=.*/DATABASE_HOST=a0c_db/' -e 's/^DATABASE_PORT=.*/DATABASE_PORT=5432/' \
  -e 's/^DATABASE_USERNAME=.*/DATABASE_USERNAME=postgres/' -e 's/^DATABASE_PASSWORD=.*/DATABASE_PASSWORD=postgres/' \
  "$work/env" >"$work/admin.env"
echo DISABLE_DATABASE_ENVIRONMENT_CHECK=1 >>"$work/admin.env"

app -d --name a0c_probe "$IMAGE" cloud-entrypoint.sh true >/dev/null
wait_until '[ "$(docker inspect -f "{{.State.Status}}" a0c_probe)" = exited ]' "the web entrypoint did not get through PgBouncer"
[ "$(docker inspect -f '{{.State.ExitCode}}' a0c_probe)" = 0 ] || fail "the web entrypoint failed on an empty database"
docker rm a0c_probe >/dev/null
[ "$(sql "SELECT to_regclass('public.schema_migrations') IS NULL")" = t ] || fail "the web entrypoint migrated"
docker exec a0c_db psql -w "host=a0c_bouncer port=6432 dbname=dawarich_cloud user=dawarich_cloud" -c 'SELECT 1' 2>&1 \
  | grep -q 'no password supplied' || fail "PgBouncer accepts a login without a password"

docker run --rm --label "$run" --network "$net" --env-file "$work/admin.env" "$IMAGE" bin/rails db:schema:load >/dev/null
sql "DO \$\$ DECLARE t record; BEGIN FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'spatial_ref_sys' LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO dawarich_cloud', t.tablename); END LOOP; END \$\$" >/dev/null

app --rm "$IMAGE" $(procfile release) >"$work/release1.log" 2>&1 || { cat "$work/release1.log" >&2; fail "release failed"; }
grep -q 'Phoenix migrations failed' "$work/release1.log" || fail "release hid the Phoenix failure"
grep -q 'permission denied for database dawarich_cloud' "$work/release1.log" \
  || { cat "$work/release1.log" >&2; fail "the release's Phoenix failure is not the missing CREATE privilege"; }
[ "$(sql "SELECT to_regnamespace('phoenix') IS NULL AND to_regnamespace('oban') IS NULL")" = t ] \
  || fail "Phoenix schemas appeared without the CREATE privilege"

app -d --name a0c_web -p 127.0.0.1:3901:5000 "$IMAGE" $(procfile web) >/dev/null
wait_until "$healthy" "Rails did not come up without Phoenix"
if docker exec a0c_web pgrep -x beam.smp >/dev/null; then
  fail "Phoenix started without its schemas"
fi
[ "$(proc_user a0c_web '^puma [0-9]')" = 32767 ] || fail "Puma runs as root or is missing"
docker logs a0c_web 2>&1 | grep -q 'schemas are missing, unreadable or behind this image; starting Rails without the Phoenix supervisor' \
  || fail "fail-open warning missing or without its cause"
docker rm -f a0c_web >/dev/null

sql "CREATE SCHEMA phoenix AUTHORIZATION dawarich_cloud; CREATE SCHEMA oban AUTHORIZATION dawarich_cloud" >/dev/null
app --rm "$IMAGE" $(procfile release) >"$work/release2.log" 2>&1 || { cat "$work/release2.log" >&2; fail "second release failed"; }
if grep -q 'Phoenix migrations failed' "$work/release2.log"; then
  cat "$work/release2.log" >&2
  fail "Phoenix migrations failed with pre-created schemas"
fi
[ "$(sql "SELECT count(*) FROM oban.phoenix_schema_migrations")" = 1 ] || fail "oban ledger incomplete"
[ "$(sql "SELECT to_regclass('phoenix.phoenix_schema_migrations') IS NOT NULL")" = t ] || fail "phoenix ledger missing"

app -d --name a0c_web -p 127.0.0.1:3901:5000 "$IMAGE" $(procfile web) >/dev/null
wait_until "$healthy" "web did not come up under Phoenix"
[ "$(docker exec a0c_web ps -o user=,comm= -C beam.smp | tr -s ' ' | sed 's/^ //')" = "32767 beam.smp" ] \
  || fail "the BEAM is missing or runs as root"
under_beam a0c_web || fail "Puma is missing or not a descendant of the BEAM"
[ "$(proc_user a0c_web '^puma [0-9]')" = 32767 ] || fail "Puma runs as root"
[ "$(docker exec a0c_web stat -c %u /var/app/tmp/dawarich.cookie)" = 32767 ] || fail "cookie not owned by the app user"
[ "$(docker exec a0c_web timeout 30 dawarich rpc 'IO.puts(Oban.config().prefix)')" = oban ] || fail "rpc failed"
docker stop a0c_web >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' a0c_web)" = 0 ] || fail "unclean web stop"
docker logs a0c_web 2>&1 | tail -20 | grep -qi goodbye || fail "puma did not shut down gracefully"

app -d --name a0c_worker "$IMAGE" $(procfile worker) >/dev/null
wait_until 'docker exec a0c_worker pgrep -f "^sidekiq [0-9]" >/dev/null' "sidekiq did not boot"
[ "$(proc_user a0c_worker '^sidekiq [0-9]')" = 32767 ] || fail "Sidekiq runs as root or is missing"
docker stop a0c_worker >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' a0c_worker)" = 0 ] || fail "unclean sidekiq stop"

[ "$(sql "SELECT count(*) FROM users")" = 0 ] || fail "seeds ran"
echo "cloud smoke: ok"
