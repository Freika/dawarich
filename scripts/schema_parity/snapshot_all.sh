#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
require_pg17
mkdir -p "$work"
releases="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("states").map { _1.fetch("first_release") }' "$root/db/release_migrations.json")" || {
  echo "cannot read the states from db/release_migrations.json" >&2
  exit 1
}
[ -n "$releases" ] || { echo "db/release_migrations.json lists no states" >&2; exit 1; }
: > "$work/failures.txt"
for release in $releases; do
  log="$work/$release.log"
  echo "== $(date -u +%Y-%m-%dT%H:%M:%SZ) snapshot.sh $release" >> "$log"
  "$root/scripts/schema_parity/snapshot.sh" "$release" >> "$log" 2>&1 || echo "$release $(tail -n 1 "$log")" >> "$work/failures.txt"
done
failed="$(wc -l < "$work/failures.txt" | tr -d ' ')"
echo "failures: $failed"
[ "$failed" -eq 0 ]
