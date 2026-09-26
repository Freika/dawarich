#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-default-names.XXXXXX")"
failures=0

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'scripts/schema_parity/lib.sh:%s\n' 'db_container="${SP_DB_CONTAINER:-sp-db}"' \
  'redis_container="${SP_REDIS_CONTAINER:-sp-redis}"' 'db_port="${SP_DB_PORT:-55532}"' \
  'redis_port="${SP_REDIS_PORT:-56479}"' > "$scratch/defaults"

named() {
  (cd "$root" && grep -H -E 'sp-db|sp-redis|55532|56479' scripts/schema_parity/*.sh scripts/schema_parity/*.rb \
    scripts/schema_parity/ci/*)
}

named > "$scratch/found"
[ "$(grep -c -x -F -f "$scratch/defaults" "$scratch/found")" -eq 4 ]
verdict $? "lib.sh holds the four default names and ports"
grep -v -x -F -f "$scratch/defaults" "$scratch/found" > "$scratch/hits"
[ ! -s "$scratch/hits" ]
verdict $? "no harness script names sp-db, sp-redis, 55532 or 56479 outside lib.sh's defaults ($(tr '\n' ' ' < "$scratch/hits"))"

echo "$failures failed"
[ "$failures" -eq 0 ]
