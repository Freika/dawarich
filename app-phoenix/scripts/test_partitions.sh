#!/bin/sh
set -eu

partitions=${1:-}
case "$partitions" in
  1|2|3|4) shift ;;
  *) echo "usage: $0 <1..4> --seed <seed> [mix test arguments]" >&2; exit 64 ;;
esac
if [ "${1:-}" != --seed ] || [ -z "${2:-}" ]; then
  echo "usage: $0 <1..4> --seed <seed> [mix test arguments]" >&2
  exit 64
fi
seed=$2
shift 2
case "$seed" in
  *[!0-9]*|'') echo "seed must be a non-negative integer" >&2; exit 64 ;;
esac

cd "$(dirname "$0")/.."
export PATH="$HOME/.asdf/shims:$PATH"
export ASDF_ERLANG_VERSION=27.3.4.1 ASDF_ELIXIR_VERSION=1.18.3-otp-27
export DATABASE_HOST=127.0.0.1 MIX_ENV=test
export PHOENIX_TEST_DATABASE=${PHOENIX_TEST_DATABASE:-dawarich_phoenix_test_part}
export PHOENIX_TEST_REDIS_URL=${PHOENIX_TEST_REDIS_URL:-redis://127.0.0.1:7271/1}
unset MIX_TEST_PARTITION

logs=${PHOENIX_TEST_PARTITION_LOG_DIR:-tmp/partition-logs}
mkdir -p "$logs"
pids=""
partition=1
while [ "$partition" -le "$partitions" ]; do
  MIX_TEST_PARTITION=$partition mix test --partitions "$partitions" --seed "$seed" "$@" \
    > "$logs/partition-$partition.log" 2>&1 &
  pids="$pids $!"
  partition=$((partition + 1))
done

failed=0
partition=1
for pid in $pids; do
  if wait "$pid"; then status=0; else status=$?; failed=1; fi
  log="$logs/partition-$partition.log"
  cat "$log" || failed=1
  summaries=$(grep -Ec '^[0-9]+ tests?, [0-9]+ failures?' "$log" || true)
  seeds=$(grep -Ec "^Running ExUnit with seed: $seed," "$log" || true)
  if [ "$summaries" -ne 1 ] || [ "$seeds" -ne 1 ]; then
    echo "partition $partition: missing or ambiguous summary/seed (exit $status)" >&2
    failed=1
  fi
  echo "partition $partition seed: $seed (exit $status, log: $log)"
  partition=$((partition + 1))
done

for partition in $(seq 1 "$partitions"); do
  cat "$logs/partition-$partition.log" || true
done | awk '/^[0-9]+ tests?, [0-9]+ failures?/ {tests += $1; failures += $3}
            END {printf "%d tests, %d failures\n", tests, failures; exit failures != 0}' \
  || failed=1
exit "$failed"
