#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
E2E_REPO="${E2E_REPO:-$HOME/projects/dawarich/e2e-dawarich-playwright/.worktrees/phoenix-port}"
ENV_FILE="${ENV_FILE:-$root/../../.env}"
PORT="${PORT:-3120}"
REDIS_PORT="${REDIS_PORT:-$((PORT + 4000))}"
DATABASE_NAME="${DATABASE_NAME:-dawarich_e2e_a2}"
rel="$root/app-phoenix/_build/prod/rel/dawarich/bin/dawarich"
pidfile="$root/tmp/pids/proxy_stack.pid"
log="$root/log/proxy_stack.log"
sidekiq_log="$root/log/proxy_stack_sidekiq.log"
sidekiq="sidekiq.* $(basename "$root") "

stack() {
  env $(grep -E '^DATABASE_(PORT|USERNAME|PASSWORD)=' "$ENV_FILE" | xargs) \
    DATABASE_HOST=127.0.0.1 DATABASE_NAME="$DATABASE_NAME" RAILS_ENV=test \
    REDIS_URL="redis://127.0.0.1:$REDIS_PORT" SELF_HOSTED=true \
    E2E_DEMO_DATA="$E2E_REPO/fixtures/demo_data.json" SMTP_FROM=e2e@dawarich.test E2E_SMTP_PORT=1025 SMTP_SERVER=127.0.0.1 \
    OTP_ENCRYPTION_PRIMARY_KEY=e2e-otp-primary-key-not-a-secret \
    OTP_ENCRYPTION_DETERMINISTIC_KEY=e2e-otp-deterministic-key-not-a-secret \
    OTP_ENCRYPTION_KEY_DERIVATION_SALT=e2e-otp-derivation-salt-not-a-secret \
    WEB_CONCURRENCY=0 RAILS_MAX_THREADS=10 APPLICATION_HOSTS="${APPLICATION_HOSTS:-localhost,127.0.0.1}" DAWARICH_COOKIE_FILE="$root/tmp/proxy_stack.cookie" \
    DAWARICH_RAILS_ROUTES="${DAWARICH_RAILS_ROUTES:-}" "$@"
}

if [ "${1:-}" = --down ]; then
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
  pkill -f "$sidekiq" 2>/dev/null || true
  tries=0
  while { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; } || pgrep -f "$sidekiq" >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || { echo "the stack did not stop" >&2; exit 1; }
    sleep 1
  done
  redis-cli -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
  rm -f "$pidfile"
  exit 0
fi

if [ "${1:-}" = --seed ]; then
  cd "$root"
  stack env E2E_B9_B11_FIXTURES=1 bin/rails ${EXTRA_SEEDS:?EXTRA_SEEDS names the seed tasks} >>"$root/log/proxy_stack_seed.log" 2>&1 \
    || { tail -20 "$root/log/proxy_stack_seed.log" >&2; exit 1; }
  exit 0
fi

case "${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)}" in
  unix://*) ;;
  *) echo "the Docker engine is not local" >&2; exit 1 ;;
esac
[ -f "$ENV_FILE" ] || { echo "$ENV_FILE with the DATABASE_* settings is missing" >&2; exit 1; }
if epmd -names 2>/dev/null | grep -q '^name dawarich at'; then
  echo "another local Dawarich release is running (rel/env.sh.eex fixes RELEASE_NODE=dawarich@localhost); stop it first" >&2
  exit 1
fi
if curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; then echo "port $PORT is in use" >&2; exit 1; fi
if pgrep -f "$sidekiq" >/dev/null 2>&1; then echo "a Sidekiq from an earlier run is still up; run $0 --down first" >&2; exit 1; fi
mkdir -p "$root/log" "$root/tmp/pids"
touch "$log" "$sidekiq_log"
log_from=$(($(wc -c <"$log") + 1))
redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1 \
  || redis-server --port "$REDIS_PORT" --bind 127.0.0.1 --save "" --appendonly no --daemonize yes --dir "$root/tmp"
curl -fsS -m 2 http://127.0.0.1:8025/api/v1/info >/dev/null 2>&1 \
  || docker run -d --rm --name e2e-mailpit -p 127.0.0.1:1025:1025 -p 127.0.0.1:8025:8025 axllent/mailpit >/dev/null

cd "$root"
stack bin/rails db:prepare >/dev/null
stack bin/rails phoenix:i18n phoenix:achievements >/dev/null
[ -n "$(ls -A public/assets 2>/dev/null)" ] || stack bin/rails assets:precompile >/dev/null
stack bin/rails phoenix:importmap phoenix:time_zones >/dev/null
(cd app-phoenix && stack env PATH="$HOME/.asdf/shims:$PATH" \
  ASDF_ERLANG_VERSION=27.3.4.1 ASDF_ELIXIR_VERSION=1.18.3-otp-27 \
  DATABASE_HOST=127.0.0.1 PHOENIX_TEST_REDIS_URL="redis://127.0.0.1:$REDIS_PORT/1" \
  MIX_ENV=prod sh -c 'mix --version | grep -q "^Mix 1.18.3 " && mix compile --force >/dev/null && mix release --overwrite >/dev/null')
stack "$rel" eval 'Dawarich.Release.migrate()'
stack DAWARICH_RAILS_ARGS="$(printf '%s\037' bundle exec bin/rails server -p "$PORT")" \
  sh -c 'echo $$ >"$1"; exec nohup "$2" start' _ "$pidfile" "$rel" >>"$log" 2>&1 &

tries=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -m 5 \
  -H "Host: ${PROXY_READY_HOST:-127.0.0.1:$PORT}" -H "X-Forwarded-Proto: ${APPLICATION_PROTOCOL:-http}" \
  "http://127.0.0.1:$PORT/users/sign_in")" = 200 ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || { tail -40 "$log" >&2; exit 1; }
  sleep 3
done
if [ "${DAWARICH_PROXY:-}" = off ]; then
  tail -c "+$log_from" "$log" | grep -q 'Phoenix proxy off (DAWARICH_PROXY=off)' || { echo "the kill switch was not honoured" >&2; exit 1; }
else
  tail -c "+$log_from" "$log" | grep -q "Phoenix listens on 127.0.0.1:$PORT and proxies to Puma" || { echo "Phoenix is not in front" >&2; exit 1; }
fi

sidekiq_from=$(($(wc -c <"$sidekiq_log") + 1))
stack nohup bundle exec sidekiq >>"$sidekiq_log" 2>&1 &
tries=0
until tail -c "+$sidekiq_from" "$sidekiq_log" | grep -q 'Running in ruby'; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || { echo "sidekiq did not boot" >&2; exit 1; }
  sleep 1
done
stack bin/rails e2e:reset_and_seed >"$root/log/proxy_stack_seed.log" 2>&1 || { tail -20 "$root/log/proxy_stack_seed.log" >&2; exit 1; }
[ -z "${EXTRA_SEEDS:-}" ] || "$root/app-phoenix/scripts/proxy_stack.sh" --seed
echo "BASE_URL=http://127.0.0.1:$PORT"
