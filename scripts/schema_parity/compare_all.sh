#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
mkdir -p "$work"
releases="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("states").map { _1.fetch("first_release") }' "$root/db/release_migrations.json")" || {
  echo "cannot read the states from db/release_migrations.json" >&2
  exit 1
}
[ -n "$releases" ] || { echo "db/release_migrations.json lists no states" >&2; exit 1; }
failed=0
compare_into() {
  summary="$1"
  shift
  echo "== $(date -u +%Y-%m-%dT%H:%M:%SZ) compare.sh $*" >> "$work/compare.log"
  if line="$("$root/scripts/schema_parity/compare.sh" "$@" 2>> "$work/compare.log")"; then
    echo "$line" >> "$summary"
  else
    echo "$* failed" >> "$summary"
    failed=$((failed + 1))
  fi
}
: > "$work/summary.txt"
for release in $releases; do
  compare_into "$work/summary.txt" "$release"
done
: > "$work/summary_schemarb.txt"
for file in "$snapshots"/*.schemarb.sql.gz; do
  [ ! -e "$file" ] || compare_into "$work/summary_schemarb.txt" "$(basename "$file" .schemarb.sql.gz)" "$file"
done
echo "compared $(wc -l < "$work/summary.txt" | tr -d ' ') states and $(wc -l < "$work/summary_schemarb.txt" | tr -d ' ') schema.rb variants, $failed failed"
[ "$failed" -eq 0 ]
