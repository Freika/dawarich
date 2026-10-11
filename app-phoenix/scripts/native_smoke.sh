#!/bin/bash
set -euo pipefail
: "${NATIVE_IMAGE:?native image required}"
: "${RAILS_FALLBACK_IMAGE:?separate Rails image required}"
: "${NATIVE_PLAYWRIGHT_ROOT:?installed Playwright package root required}"
: "${NATIVE_SMOKE_OUT:?evidence directory required}"
: "${NATIVE_SMOKE_DATABASE:?private database name required}"
[[ $NATIVE_SMOKE_DATABASE =~ ^[a-zA-Z0-9_]{1,63}$ ]] || exit 64
CONTEXT=${NATIVE_DOCKER_CONTEXT:-orbstack}
case "$CONTEXT" in orbstack|colima) ;; *) exit 64;; esac
RUN=${NATIVE_SMOKE_RUN:-$(date +%Y%m%d%H%M%S)-$$}
[[ $RUN =~ ^[a-zA-Z0-9-]+$ ]] || exit 64
ROOT=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$NATIVE_SMOKE_OUT"
PRIVATE=$(mktemp -d)
chmod 700 "$PRIVATE"
NET=x4-$RUN PG=x4-$RUN-pg REDIS=x4-$RUN-redis APP=x4-$RUN-app VOL=x4-$RUN-data
OWNED=()
NETWORK=0 VOLUME=0
export NATIVE_SMOKE_SESSION="$PRIVATE/session.json"
dk() { docker --context "$CONTEXT" "$@"; }
cleanup() {
  result=$?
  trap - EXIT
  for name in ${OWNED[@]+"${OWNED[@]}"}; do
    if [ "$(dk inspect -f '{{index .Config.Labels "org.dawarich.x4"}}' "$name" 2>/dev/null)" = "$RUN" ]; then
      dk logs "$name" >"$NATIVE_SMOKE_OUT/$name.log" 2>&1 || true
      dk rm -fv "$name" >/dev/null 2>&1 || true
    fi
  done
  [ "$NETWORK" = 0 ] || dk network rm "$NET" >/dev/null
  [ "$VOLUME" = 0 ] || dk volume rm "$VOL" >/dev/null
  python3 - "$PRIVATE" "$NATIVE_SMOKE_OUT" <<'REDACT'
import pathlib,sys
secrets=[]
for env in pathlib.Path(sys.argv[1]).glob('*.env'):
    for line in env.read_text().splitlines():
        key,sep,value=line.partition('=')
        if sep and value and any(word in key for word in ['PASSWORD','SECRET','API_KEY']): secrets.append(value)
for log in pathlib.Path(sys.argv[2]).glob('*.log'):
    text=log.read_text(errors='replace')
    for value in secrets: text=text.replace(value,'[REDACTED]')
    log.write_text(text)
REDACT
  rm -rf "$PRIVATE"
  printf '%s\n' "$result" >"$NATIVE_SMOKE_OUT/exit.status"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
for name in "$PG" "$REDIS" "$APP"; do
  if dk container inspect "$name" >/dev/null 2>&1; then echo 'resource name already exists' >&2; exit 64; fi
done
for pair in "network:$NET" "volume:$VOL"; do
  if dk "${pair%%:*}" inspect "${pair#*:}" >/dev/null 2>&1; then echo 'resource name already exists' >&2; exit 64; fi
done
dk network create --label org.dawarich.x4="$RUN" "$NET" >/dev/null; NETWORK=1
dk volume create --label org.dawarich.x4="$RUN" "$VOL" >/dev/null; VOLUME=1
export NATIVE_SMOKE_API_KEY=$(openssl rand -hex 32)
PASSWORD=$(openssl rand -hex 24)
printf 'POSTGRES_PASSWORD=%s\nPOSTGRES_DB=%s\n' "$PASSWORD" "$NATIVE_SMOKE_DATABASE" >"$PRIVATE/pg.env"
cat >"$PRIVATE/app.env" <<ENV
SELF_HOSTED=true
DATABASE_HOST=$PG
DATABASE_PORT=5432
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=$PASSWORD
DATABASE_NAME=$NATIVE_SMOKE_DATABASE
REDIS_URL=redis://$REDIS:6379/0
PHOENIX_TEST_REDIS_URL=redis://$REDIS:6379/1
PHOENIX_TEST_DATABASE=$NATIVE_SMOKE_DATABASE
RAILS_ENV=test
RAILS_PORT=3000
SECRET_KEY_BASE=$(openssl rand -hex 64)
NATIVE_SMOKE_API_KEY=$NATIVE_SMOKE_API_KEY
APPLICATION_HOSTS=localhost,127.0.0.1
DOMAIN=127.0.0.1
RAILS_SERVE_STATIC_FILES=true
WEB_CONCURRENCY=1
DAWARICH_RAILS=off
DAWARICH_PHOENIX_LIFECYCLE=true
OTP_ENCRYPTION_PRIMARY_KEY=synthetic-otp-primary-key-not-a-secret
OTP_ENCRYPTION_DETERMINISTIC_KEY=synthetic-otp-deterministic-key-not-a-secret
OTP_ENCRYPTION_KEY_DERIVATION_SALT=synthetic-otp-derivation-salt-not-a-secret
ENV
chmod 600 "$PRIVATE/"*.env
OWNED+=("$PG")
dk run -d --pull=never --name "$PG" --network "$NET" --label org.dawarich.x4="$RUN" --env-file "$PRIVATE/pg.env" -e POSTGRES_INITDB_ARGS='--locale-provider=icu --icu-locale=en-US' -v "$VOL:/var/lib/postgresql/data" postgis/postgis:17-3.5-alpine >/dev/null
OWNED=("$REDIS" "${OWNED[@]}")
dk run -d --pull=never --name "$REDIS" --network "$NET" --label org.dawarich.x4="$RUN" redis:7.4-alpine >/dev/null
for n in {1..90}; do dk exec "$PG" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
OWNED=("$APP" "${OWNED[@]}")
dk run -d --pull=never --name "$APP" --network "$NET" --label org.dawarich.x4="$RUN" --env-file "$PRIVATE/app.env" -p 127.0.0.1::3000 "$NATIVE_IMAGE" bin/rails server -b 0.0.0.0 -p 3000 >/dev/null
url() { printf 'http://127.0.0.1:%s' "$(dk port "$APP" 3000/tcp | cut -d: -f2)"; }
wait_app() {
  for n in {1..180}; do
    curl -sf --max-time 3 "$(url)/api/v1/health" >/dev/null && return 0
    [ "$(dk inspect -f '{{.State.Running}}' "$APP")" = true ] || return 1
    sleep 2
  done
  return 1
}
wait_app
[ "$(dk exec "$APP" dawarich rpc 'IO.puts(Dawarich.Release.readiness())')" = ready ]
dk exec "$APP" sh -c 'for tool in ruby bundle gem rake rails puma sidekiq; do ! command -v "$tool" >/dev/null || exit 1; done'
dk exec "$APP" sh -c 'ps -eo comm=' >"$NATIVE_SMOKE_OUT/native-process-names.txt"
! grep -Ei 'ruby|puma|nginx|sidekiq' "$NATIVE_SMOKE_OUT/native-process-names.txt"
dk cp "$ROOT/native_package.mjs" "$APP:/tmp/native_package.mjs"
dk exec "$APP" sh -c 'node /tmp/native_package.mjs /var/app /opt/dawarich/lib/dawarich-*/priv' >"$NATIVE_SMOKE_OUT/payload.json"
for file in seed render; do
  dk cp "$ROOT/native_smoke_$file.exs" "$APP:/tmp/smoke_$file.exs"
  dk exec "$APP" dawarich rpc "Code.eval_file(\"/tmp/smoke_$file.exs\")" >"$NATIVE_SMOKE_OUT/$file.log" 2>&1
done
NATIVE_SMOKE_URL=$(url) NATIVE_SMOKE_RECEIPT="$NATIVE_SMOKE_OUT/native.json" node "$ROOT/native_smoke.mjs" >"$NATIVE_SMOKE_OUT/native-browser.log" 2>&1
dk logs "$APP" >"$NATIVE_SMOKE_OUT/native-app.log" 2>&1
dk rm -fv "$APP" >/dev/null
sed -e 's/DAWARICH_RAILS=off/DAWARICH_RAILS=on/' -e 's/DAWARICH_PHOENIX_LIFECYCLE=true/DAWARICH_PHOENIX_LIFECYCLE=false/' "$PRIVATE/app.env" >"$PRIVATE/rails.env"
dk run -d --pull=never --name "$APP" --network "$NET" --label org.dawarich.x4="$RUN" --env-file "$PRIVATE/rails.env" -p 127.0.0.1::3000 --entrypoint bundle "$RAILS_FALLBACK_IMAGE" exec rails server -b 0.0.0.0 -p 3000 >/dev/null
wait_app
NATIVE_SMOKE_URL=$(url) NATIVE_SMOKE_MODE=rails NATIVE_SMOKE_RECEIPT="$NATIVE_SMOKE_OUT/rails.json" node "$ROOT/native_smoke.mjs" >"$NATIVE_SMOKE_OUT/rails-browser.log" 2>&1
dk exec "$APP" sh -c 'ps -eo comm=' >"$NATIVE_SMOKE_OUT/rails-process-names.txt"
! grep -E 'beam' "$NATIVE_SMOKE_OUT/rails-process-names.txt"
printf 'PASS native image and independent whole-app Rails fallback\n'
