#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
mkdir -p "$work"
tmpd="$(mktemp -d "$work/.tmp.XXXXXX")"
cleanup() {
  rm -rf "$tmpd"
  docker exec sp-db dropdb -U postgres --if-exists sp_baseline >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

recreate_db sp_baseline
(cd "$root" && env $rails_env DATABASE_NAME=sp_baseline \
  bin/rails runner scripts/schema_parity/rails_reference.rb schema "$tmpd/baseline" >/dev/null)
out="$root/app-phoenix/priv/release_migrations/baseline.sql"
mkdir -p "$(dirname "$out")"
mv "$tmpd/baseline.sql" "$out"
versions="$(ruby -e 'puts File.read(ARGV[0])[/INSERT INTO "schema_migrations".*/m].to_s.scan(/\b\d{14}\b/).uniq.size' "$out")"
[ "$versions" -gt 0 ] || { echo "no schema_migrations versions in $out" >&2; exit 1; }
echo "wrote $out: $(grep -c ';$' "$out") statements, $versions ledger versions"
