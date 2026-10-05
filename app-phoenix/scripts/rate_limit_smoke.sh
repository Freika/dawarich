#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

IMAGE="${IMAGE:-dawarich:a13c-local}"
POSTGIS_IMAGE="${POSTGIS_IMAGE:-postgis/postgis:17-3.5-alpine}"
MODE="${MODE:-smoke}"
KEEP="${KEEP:-0}"
WAIT="${SMOKE_WAIT_SECONDS:-300}"
pool_size=4
if [ "$MODE" = bench ]; then
  [ -n "${BENCH_REPORT:-}" ] || { echo 'BENCH_REPORT is required' >&2; exit 1; }
  case "${BENCH_ROLE:-}" in
    base) ;;
    branch) [ -f "${BENCH_BASELINE:-}" ] || { echo 'branch requires BENCH_BASELINE' >&2; exit 1; } ;;
    *) echo 'BENCH_ROLE must be base or branch' >&2; exit 1 ;;
  esac
fi
net=a13c-rate
run="a13c-smoke=$$"
manager=https://manager.example
throttled='{"error":"rate_limit_exceeded","message":"API rate limit exceeded. Please wait before making more requests.","upgrade_url":"'
fail() {
  echo "$1" >&2
  exit 1
}

case "${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)}" in
  unix://*) ;;
  *) fail "the Docker engine is not local; never run this against a remote engine such as dawarich-swarm" ;;
esac
if docker ps -a --format '{{.Names}}' | grep -q '^a13c_'; then
  fail "a13c_* containers already exist; remove them first"
fi
for port in 3911 3912; do
  code=0
  curl -s -m 5 -o /dev/null "http://127.0.0.1:$port/" || code=$?
  [ "$code" = 7 ] || fail "port $port is in use"
done

work="$(mktemp -d "$PWD/tmp/a13c-rate.XXXXXX")"
cleanup() {
  ec=$?
  if [ "$ec" -ne 0 ]; then
    for c in a13c_web a13c_web2; do
      docker logs --tail 40 "$c" 2>&1 | sed "s/^/[$c] /" >&2 || true
    done
  fi
  if [ "$KEEP" = 1 ] && [ "$ec" -eq 0 ]; then
    echo "kept; remove with: docker rm -fv \$(docker ps -aq --filter label=$run) && docker network rm $net && docker rmi a13c-pgbouncer:local"
  else
    docker rm -fv $(docker ps -aq --filter "label=$run") >/dev/null 2>&1 || true
    docker network rm $(docker network ls -q --filter "label=$run") >/dev/null 2>&1 || true
    docker rmi -f a13c-pgbouncer:local >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
  exit "$ec"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

procfile() { sed -n "s/^$1: //p" Procfile.cloud; }
sql() { docker exec a13c_db psql -U postgres -d dawarich_cloud -Atc "$1"; }
app() { docker run --init --label "$run" --network "$net" --env-file "$work/env" "$@"; }

wait_until() {
  tries=0
  until eval "$1"; do
    tries=$((tries + 1))
    [ "$tries" -lt "$WAIT" ] || fail "$2"
    sleep 1
  done
}

healthy() { curl -fsS -m 5 "http://127.0.0.1:$1/api/v1/health" 2>/dev/null | grep -q '"status"'; }

web() {
  name=$1
  port=$2
  shift 2
  if [ "$MODE" = bench ] && [ "$BENCH_ROLE" = base ]; then
    app -d --name "$name" -p "127.0.0.1:$port:5000" "$@" --entrypoint web-entrypoint.sh "$IMAGE" bin/rails server -p 5000 -b :: >/dev/null
  else
    app -d --name "$name" -p "127.0.0.1:$port:5000" "$@" "$IMAGE" $(procfile web) >/dev/null
  fi
  wait_until "healthy $port" "$name did not come up"
}

post() {
  curl -s -m 10 -o "$work/body" -D "$work/head" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -H "X-Forwarded-For: $2" --data "$3" "http://127.0.0.1:$1$4"
}

login() { post "$1" "$2" "{\"email\":\"$3\",\"password\":\"x\"}" /api/v1/auth/login; }

counter() {
  sql "SELECT coalesce(sum(value), 0) FROM phoenix.counters WHERE key LIKE 'rack::attack:%:$1' AND expires_at > now()"
}

early_in() {
  until [ $(($(docker exec a13c_web date +%s) % $1)) -lt $(($1 - 20)) ]; do sleep 1; done
}

expect_throttled() {
  grep -qi '^content-type: application/json' "$work/head" || fail "429 content type"
  grep -qi '^cache-control: no-store' "$work/head" || fail "429 cache control"
  grep -qiE '^retry-after: [0-9]+' "$work/head" || fail "429 Retry-After"
  [ "$(cat "$work/body")" = "$throttled$1/pricing\"}" ] || fail "429 body: $(cat "$work/body")"
}

budget() {
  early_in 60
  i=1
  while [ "$i" -le 20 ]; do
    port=$1
    if [ -n "${3:-}" ] && [ $((i % 2)) = 0 ]; then port=$3; fi
    [ "$(login "$port" "$2" "u$i-$2@example.invalid")" != 429 ] || fail "login $i from $2 was throttled early"
    i=$((i + 1))
  done
  [ "$(login "$1" "$2" "u21-$2@example.invalid")" = 429 ] || fail "the 21st login from $2 was not throttled"
  [ "$(counter "logins/api_ip:$2")" = 21 ] || fail "phoenix.counters does not hold 21 logins from $2"
}

rpc() { docker exec a13c_web timeout 60 dawarich rpc "$1"; }

share=a13c0000-0000-4000-8000-000000000001
unlock() {
  curl -s -m 10 -o "$work/body" -D "$work/head" -w '%{http_code}' -X POST -H "Content-Type: $1" --data "$2" \
    "http://127.0.0.1:3911/s/$share/unlock"
}

docker network create --label "$run" "$net" >/dev/null
docker run -d --name a13c_db --label "$run" --network "$net" -e POSTGRES_PASSWORD=postgres "$POSTGIS_IMAGE" >/dev/null
docker run -d --name a13c_redis --label "$run" --network "$net" redis:7.4-alpine >/dev/null
mkdir "$work/bouncer"
cat >"$work/bouncer/pgbouncer.ini" <<EOF
[databases]
dawarich_cloud = host=a13c_db port=5432 dbname=dawarich_cloud

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
unix_socket_dir =
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = $pool_size
min_pool_size = 2
max_prepared_statements = 200
stats_users = dawarich_cloud
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
df -h /System/Volumes/Data
[ "$(df -k /System/Volumes/Data | awk 'NR == 2 {print $4}')" -ge "${SMOKE_MIN_BUILD_FREE_KIB:-15728640}" ] || fail "less than required free disk before PgBouncer build"
build_ec=0
docker build -q -t a13c-pgbouncer:local "$work/bouncer" >/dev/null || build_ec=$?
docker builder prune -af
[ "$build_ec" -eq 0 ] || fail "PgBouncer build failed ($build_ec)"
docker run -d --name a13c_bouncer --label "$run" --network "$net" a13c-pgbouncer:local >/dev/null

wait_until '[ "$(docker logs a13c_db 2>&1 | grep -c "ready to accept connections")" -ge 2 ]' "database did not start"
docker exec -i a13c_db psql -v ON_ERROR_STOP=1 -q -U postgres <<'EOF'
CREATE ROLE dawarich_cloud LOGIN PASSWORD 'cloud';
CREATE DATABASE dawarich_cloud;
\c dawarich_cloud
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
GRANT USAGE, CREATE ON SCHEMA public TO dawarich_cloud;
CREATE SCHEMA phoenix AUTHORIZATION dawarich_cloud;
CREATE SCHEMA oban AUTHORIZATION dawarich_cloud;
EOF

cat >"$work/env" <<EOF
RAILS_ENV=production
PORT=3000
DATABASE_HOST=a13c_bouncer
DATABASE_PORT=6432
DATABASE_USERNAME=dawarich_cloud
DATABASE_PASSWORD=cloud
DATABASE_NAME=dawarich_cloud
DATABASE_ADVISORY_LOCKS=false
REDIS_URL=redis://a13c_redis:6379
SELF_HOSTED=false
MANAGER_URL=$manager
SECRET_KEY_BASE=$(od -An -N64 -tx1 /dev/urandom | tr -d ' \n')
AUTH_JWT_SECRET_KEY=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
SUBSCRIPTION_WEBHOOK_SECRET=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
APPLICATION_HOSTS=localhost,127.0.0.1
WEB_CONCURRENCY=1
EOF
sed -e 's/^DATABASE_HOST=.*/DATABASE_HOST=a13c_db/' -e 's/^DATABASE_PORT=.*/DATABASE_PORT=5432/' \
  -e 's/^DATABASE_USERNAME=.*/DATABASE_USERNAME=postgres/' -e 's/^DATABASE_PASSWORD=.*/DATABASE_PASSWORD=postgres/' \
  "$work/env" >"$work/admin.env"
echo DISABLE_DATABASE_ENVIRONMENT_CHECK=1 >>"$work/admin.env"
docker run --rm --label "$run" --network "$net" --env-file "$work/admin.env" "$IMAGE" bin/rails db:schema:load >/dev/null
sql "DO \$\$ DECLARE t record; BEGIN FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'spatial_ref_sys' LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO dawarich_cloud', t.tablename); END LOOP; END \$\$" >/dev/null
if [ "$MODE" != bench ] || [ "$BENCH_ROLE" != base ]; then
  app --rm "$IMAGE" $(procfile release) >"$work/release.log" 2>&1 || { cat "$work/release.log" >&2; fail "release failed"; }
  [ "$(sql "SELECT to_regclass('phoenix.counters') IS NOT NULL")" = t ] || fail "phoenix.counters is missing after the release"
fi

if [ "$MODE" = bench ]; then
  web a13c_web 3911
  app --rm "$IMAGE" bin/rails runner "u = User.create!(email: 'a13c-bench@dawarich.test', password: 'a13c-bench-password', skip_auto_trial: true); u.update_columns(api_key: 'a13cbenchqqqqqqqqqqqqqqq', plan: User.plans[:pro], active_until: 1.year.from_now); Point.insert_all!([{ user_id: u.id, timestamp: Time.utc(2026, 1, 1, 12).to_i, lonlat: 'POINT(1 1)', created_at: Time.current, updated_at: Time.current }])" >/dev/null
  [ -z "${BENCH_BASELINE:-}" ] || cp "$BENCH_BASELINE" "$work/baseline.json"
  bench_rc=0
  docker run --rm --init --label "$run" --network container:a13c_web --env-file "$work/env" --entrypoint ruby \
    -v "$PWD/app-phoenix/scripts/rate_limit_bench.rb:/bench.rb:ro" -v "$work:/bench" -e PGPASSWORD=cloud     -e BENCH_IN_CONTAINER=1 -e BENCH_URL=http://127.0.0.1:5000 -e BENCH_POOL_SIZE="$pool_size"     -e BENCH_ROLE -e BENCH_REPORT=/bench/report.json -e BENCH_BASELINE=/bench/baseline.json     "${BENCH_RUNNER_IMAGE:-$IMAGE}" /bench.rb || bench_rc=$?
  [ "$bench_rc" -ne 0 ] || [ -s "$work/report.json" ] || fail "benchmark report was not persisted"
  [ ! -f "$work/report.json" ] || cp "$work/report.json" "$BENCH_REPORT"
  exit "$bench_rc"
fi

web a13c_web 3911
docker logs a13c_web 2>&1 | grep -q 'Phoenix listens on .*:5000 and proxies to Puma' || fail "Phoenix does not front Puma"

budget 3911 203.0.113.21
expect_throttled "$manager"
[ -z "$(docker exec a13c_redis redis-cli -n 3 --scan --pattern 'rack::attack*')" ] || fail "rack-attack still writes Redis"

early_in 60
rpc 'body = ~s({"email":"shared@example.invalid"})
  for _ <- 1..4 do
    conn = Plug.Test.conn(:post, "/api/v1/auth/login", body) |> Plug.Conn.put_req_header("content-type", "application/json") |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(body)))
    {:pass, _conn, [_, _], nil} = DawarichWeb.RateLimit.decide(conn, %{now: System.os_time(:second), plan: fn _ -> nil end, repo: Dawarich.Jobs.repo(), self_hosted: false})
  end
  IO.puts("counted")' | grep -q counted || fail "Phoenix could not count through PgBouncer"
[ "$(post 3911 203.0.113.22 '{"email":"shared@example.invalid"}' /api/v1/auth/login)" != 429 ] || fail "Rails throttled before the shared budget was spent"
[ "$(post 3911 203.0.113.22 '{"email":"shared@example.invalid"}' /api/v1/auth/login)" = 429 ] || fail "Rails did not see the four logins Phoenix counted"
[ "$(counter 'logins/api_email:shared@example.invalid')" = 6 ] || fail "the shared email budget is not 6"

early_in 60
rpc 'body = ~s({"email":"released@example.invalid"})
  for _ <- 1..3 do
    conn = Plug.Test.conn(:post, "/api/v1/auth/login", body)
    %{conn | host: "127.0.0.1", req_headers: [{"host", "127.0.0.1:3911"} | conn.req_headers]}
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> DawarichWeb.RateLimit.call([])
    |> Plug.Conn.assign(:api_tag, "smoke")
    |> DawarichWeb.Api.Body.replay("smoke")
  end
  IO.puts("replayed")' | grep -q replayed || fail "a counted request could not be handed to Puma"
[ "$(counter 'logins/api_email:released@example.invalid')" = 3 ] || fail "a request Phoenix handed to Puma was not counted exactly once"

web a13c_web2 3912
budget 3911 203.0.113.23 3912

docker rm -f a13c_web a13c_web2 >/dev/null
web a13c_web 3911 -e DAWARICH_PROXY=off
docker logs a13c_web 2>&1 | grep -q 'Phoenix proxy off (DAWARICH_PROXY=off)' || fail "the kill switch was not honoured"
budget 3911 203.0.113.24

docker rm -f a13c_web >/dev/null
web a13c_web 3911 -e SELF_HOSTED=true
early_in 300
i=1
while [ "$i" -le 5 ]; do
  [ "$(post 3911 203.0.113.25 '{"phrase":"x"}' /s/a13c/unlock)" != 429 ] || fail "unlock $i was throttled early"
  i=$((i + 1))
done
[ "$(post 3911 203.0.113.25 '{"phrase":"x"}' /s/a13c/unlock)" = 429 ] || fail "the sixth unlock was not throttled on self-hosted"
expect_throttled ""
i=1
while [ "$i" -le 21 ]; do
  [ "$(login 3911 203.0.113.26 "s$i@example.invalid")" != 429 ] || fail "self-hosted throttled a login"
  i=$((i + 1))
done
[ "$(counter 'logins/api_ip:203.0.113.26')" = 0 ] || fail "self-hosted counted logins"

app --rm "$IMAGE" bin/rails runner "u = User.create!(email: 'a13c-share@dawarich.test', password: 'a13c-share-password', skip_auto_trial: true); SharedLink.create!(id: '$share', user: u, resource_type: :live, name: 'A13c', magic_phrase: 'a13c-phrase', settings: SharedLink.default_settings_for(:live))" >/dev/null
early_in 300
i=1
while [ "$i" -le 5 ]; do
  if [ $((i % 2)) = 1 ]; then
    [ "$(unlock application/x-www-form-urlencoded phrase=wrong)" = 401 ] || fail "Phoenix's shared unlock $i was not a 401"
  else
    [ "$(unlock application/json '{"phrase":"wrong"}')" != 429 ] || fail "Rails' shared unlock $i was throttled early"
  fi
  i=$((i + 1))
done
[ "$(unlock application/x-www-form-urlencoded phrase=wrong)" = 429 ] || fail "Phoenix did not see the unlocks Rails counted"
expect_throttled ""
[ "$(counter "shared_links/unlock:%:$share")" = 6 ] || fail "the shared unlock budget is not 6"

if [ "$KEEP" = 1 ]; then
  docker rm -f a13c_web >/dev/null
  web a13c_web 3911
  echo "browser stack: http://127.0.0.1:3911/users/sign_in (Cloud, Phoenix in front of Puma)"
fi
echo "rate limit smoke: ok"
