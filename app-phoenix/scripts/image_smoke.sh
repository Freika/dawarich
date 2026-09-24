#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

export DAWARICH_APP_PORT=3900
override="$(mktemp)"
cat >"$override" <<'EOF'
services:
  dawarich_redis:
    container_name: a0_redis
  dawarich_db:
    container_name: a0_db
  dawarich_app:
    container_name: a0_app
    image: dawarich:a0-local
  dawarich_sidekiq:
    container_name: a0_sidekiq
    image: dawarich:a0-local
EOF
compose="docker compose -p phoenix-a0 -f docker/docker-compose.yml -f $override"

cleanup() {
  ec=$?
  $compose down -v >/dev/null 2>&1 || true
  rm -f "$override"
  exit "$ec"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

fail() {
  echo "$1" >&2
  exit 1
}

$compose up -d
tries=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' a0_app)" = "healthy" ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || fail "app not healthy"
  sleep 5
done

docker exec a0_app ps -o comm= -p 1 | grep -q beam || fail "PID 1 is not the BEAM"
docker exec a0_app ps -eo args | grep -q '^puma' || fail "puma not running"
[ "$(docker exec a0_app dawarich rpc 'IO.puts(Oban.config().prefix)')" = "oban" ] || fail "rpc failed"
curl -fsS "http://127.0.0.1:$DAWARICH_APP_PORT/api/v1/health" | grep -q '"status"' || fail "health failed"
docker exec a0_db psql -U postgres -d dawarich_development -Atc \
  "SELECT string_agg(nspname, ',' ORDER BY nspname) FROM pg_namespace WHERE nspname IN ('oban','phoenix')" \
  | grep -qx 'oban,phoenix' || fail "schemas missing"

$compose stop dawarich_app
[ "$(docker inspect -f '{{.State.ExitCode}}' a0_app)" = "0" ] || fail "unclean stop"
docker logs a0_app 2>&1 | tail -20 | grep -qi 'goodbye' || fail "puma did not shut down gracefully"
tries=0
until docker logs a0_sidekiq 2>&1 | grep -q 'Running in ruby'; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || fail "sidekiq did not finish booting"
  sleep 1
done
$compose stop dawarich_sidekiq
[ "$(docker inspect -f '{{.State.ExitCode}}' a0_sidekiq)" = "0" ] || fail "sidekiq unclean stop"
echo "image smoke: ok"
