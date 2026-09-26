#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export LC_ALL=C.UTF-8

MIX_ENV=prod mix release --overwrite >/dev/null
for asset in _build/prod/rel/dawarich/lib/dawarich-*/priv/admin1_world.geojson; do
  [ -f "$asset" ] && [ ! -L "$asset" ] && cmp -s "$asset" ../lib/assets/admin1_world.geojson \
    || { echo "the release does not carry lib/assets/admin1_world.geojson as priv/admin1_world.geojson"; exit 1; }
done
rel=_build/prod/rel/dawarich/bin/dawarich
work="$(mktemp -d)"
export DAWARICH_COOKIE_FILE="$work/cookie"
export DATABASE_NAME="${PHOENIX_TEST_DATABASE:-dawarich_phoenix_test}"
DAWARICH_RAILS_ARGS="$(printf '%s\037' sh -c 'printf "M\303\274nchen\n"; echo "args:[$1][$2][$3] $#"; echo "cookie:${RELEASE_COOKIE:-unset}"; while [ ! -f "$0" ]; do sleep 0.1; done; exit 7' "$work/go" "" x "")"
export DAWARICH_RAILS_ARGS

"$rel" start >"$work/out" 2>&1 &
node_pid=$!

cleanup() {
  ec=$?
  if kill -0 "$node_pid" 2>/dev/null; then
    kill "$node_pid" 2>/dev/null || true
    wait "$node_pid" 2>/dev/null || true
  fi
  [ "$ec" -eq 0 ] || cat "$work/out" >&2
  exit "$ec"
}
trap cleanup EXIT

prefix=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  prefix="$("$rel" rpc 'IO.puts(Oban.config().prefix)' 2>/dev/null || true)"
  [ "$prefix" = "oban" ] && break
  sleep 1
done
[ "$prefix" = "oban" ] || { echo "rpc did not answer"; exit 1; }

mode="$(stat -c %a "$DAWARICH_COOKIE_FILE" 2>/dev/null || stat -f %Lp "$DAWARICH_COOKIE_FILE")"
[ "$mode" = "600" ] || { echo "cookie mode is $mode"; exit 1; }

touch "$work/go"
set +e
wait "$node_pid"
status=$?
set -e
[ "$status" -eq 7 ] || { echo "expected exit 7, got $status"; exit 1; }
grep -qF "$(printf 'M\303\274nchen')" "$work/out" || { echo "non-ASCII output was re-encoded"; exit 1; }
grep -qxF 'args:[][x][] 3' "$work/out" || { echo "empty arguments were dropped"; exit 1; }
grep -qxF 'cookie:unset' "$work/out" || { echo "RELEASE_COOKIE reached the Rails server"; exit 1; }

env_sh="$(ls _build/prod/rel/dawarich/releases/*/env.sh)"
mkdir -p "$work/stubs" "$work/owned" "$work/locked"
printf '#!/bin/sh\necho 0\n' >"$work/stubs/id"
printf '#!/bin/sh\necho "$*" >"%s/chown.args"\n' "$work" >"$work/stubs/chown"
chmod +x "$work/stubs/id" "$work/stubs/chown"
PATH="$work/stubs:$PATH" DAWARICH_COOKIE_FILE="$work/owned/cookie" sh "$env_sh"
[ "$(cat "$work/chown.args" 2>/dev/null)" = "$(ls -nd "$work/owned" | awk '{print $3":"$4}') $work/owned/cookie" ] \
  || { echo "a cookie created as root was not handed to its directory's owner"; exit 1; }

printf x >"$work/locked/cookie"
chmod 000 "$work/locked/cookie"
set +e
DAWARICH_COOKIE_FILE="$work/locked/cookie" sh "$env_sh" 2>/dev/null
locked=$?
set -e
chmod 600 "$work/locked/cookie"
[ "$locked" -eq 4 ] || { echo "an unreadable cookie exited $locked, not 4"; exit 1; }

rm -f "$work/chown.args"
ln -s "$work/locked/target" "$work/owned/linked"
set +e
PATH="$work/stubs:$PATH" DAWARICH_COOKIE_FILE="$work/owned/linked" sh "$env_sh" 2>/dev/null
linked=$?
set -e
[ "$linked" -eq 4 ] && [ ! -e "$work/locked/target" ] && [ ! -e "$work/chown.args" ] \
  || { echo "a symlinked cookie path was followed (exit $linked)"; exit 1; }

echo "release smoke: ok"
