#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
E2E_REPO="${E2E_REPO:-$HOME/projects/dawarich/e2e-dawarich-playwright/.worktrees/phoenix-port}"
ENV_FILE="${ENV_FILE:-$root/../../.env}"
PORT="${PORT:-3120}"
REDIS_PORT=$((PORT + 4000))
rel="$root/app-phoenix/_build/prod/rel/dawarich/bin/dawarich"
pidfile="$root/tmp/pids/proxy_stack.pid"
log="$root/log/proxy_stack.log"
sidekiq="sidekiq.* $(basename "$root") "

stack() {
  env $(grep -E '^DATABASE_(HOST|PORT|USERNAME|PASSWORD)=' "$ENV_FILE" | xargs) \
    DATABASE_NAME=dawarich_e2e_a2 REDIS_URL="redis://127.0.0.1:$REDIS_PORT" SELF_HOSTED=true \
    E2E_DEMO_DATA="$E2E_REPO/fixtures/demo_data.json" SMTP_FROM=e2e@dawarich.test E2E_SMTP_PORT=1025 SMTP_SERVER=127.0.0.1 \
    OTP_ENCRYPTION_PRIMARY_KEY=e2e-otp-primary-key-not-a-secret \
    OTP_ENCRYPTION_DETERMINISTIC_KEY=e2e-otp-deterministic-key-not-a-secret \
    OTP_ENCRYPTION_KEY_DERIVATION_SALT=e2e-otp-derivation-salt-not-a-secret \
    WEB_CONCURRENCY=0 RAILS_MAX_THREADS=10 DAWARICH_COOKIE_FILE="$root/tmp/proxy_stack.cookie" "$@"
}

if [ "${1:-}" = --down ]; then
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
  pkill -f "$sidekiq" 2>/dev/null || true
  redis-cli -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
  rm -f "$pidfile"
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
mkdir -p "$root/log" "$root/tmp/pids"
redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1 \
  || redis-server --port "$REDIS_PORT" --bind 127.0.0.1 --save "" --appendonly no --daemonize yes --dir "$root/tmp"
curl -fsS -m 2 http://127.0.0.1:8025/api/v1/info >/dev/null 2>&1 \
  || docker run -d --rm --name e2e-mailpit -p 127.0.0.1:1025:1025 -p 127.0.0.1:8025:8025 axllent/mailpit >/dev/null

cd "$root"
stack bin/rails db:prepare >/dev/null
[ -n "$(ls -A public/assets 2>/dev/null)" ] || stack bin/rails assets:precompile >/dev/null
(cd app-phoenix && env PATH="$HOME/.asdf/shims:$PATH" MIX_ENV=prod mix release --overwrite >/dev/null)
stack "$rel" eval 'Dawarich.Release.migrate()'
stack DAWARICH_RAILS_ARGS="$(printf '%s\037' bundle exec bin/rails server -p "$PORT")" nohup "$rel" start >>"$log" 2>&1 &
echo $! >"$pidfile"

tries=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:$PORT/users/sign_in")" = 200 ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || { tail -40 "$log" >&2; exit 1; }
  sleep 3
done
if [ "${DAWARICH_PROXY:-}" = off ]; then
  grep -q 'Phoenix proxy off (DAWARICH_PROXY=off)' "$log" || { echo "the kill switch was not honoured" >&2; exit 1; }
else
  grep -q "Phoenix listens on 127.0.0.1:$PORT and proxies to Puma" "$log" || { echo "Phoenix is not in front" >&2; exit 1; }
fi

pgrep -f "$sidekiq" >/dev/null 2>&1 || { stack bundle exec sidekiq >>"$root/log/proxy_stack_sidekiq.log" 2>&1 & }
tries=0
until grep -q 'Running in ruby' "$root/log/proxy_stack_sidekiq.log" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || { echo "sidekiq did not boot" >&2; exit 1; }
  sleep 1
done
stack bin/rails e2e:reset_and_seed >"$root/log/proxy_stack_seed.log" 2>&1 || { tail -20 "$root/log/proxy_stack_seed.log" >&2; exit 1; }
echo "BASE_URL=http://127.0.0.1:$PORT"
