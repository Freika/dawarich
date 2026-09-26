#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-inventory-preflight.XXXXXX")"
repo="$scratch/repo"
work="$scratch/work"
failures=0

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fresh_copy() {
  rm -rf "$repo" "$work"
  mkdir -p "$repo"
  cp -r "$root/db" "$repo/db"
  cp -r "$root/scripts" "$repo/scripts"
}

preflight() {
  LANG=en_US.UTF-8 SP_WORK="$work" ruby "$repo/scripts/schema_parity/matrix_inventory_preflight.rb" "$repo" 2>&1
}

expect_fail() {
  label="$1"
  needle="$2"
  output="$(preflight)"
  status=$?
  [ "$status" -ne 0 ]
  verdict $? "$label fails ($output)"
  contains "$output" "$needle"
  verdict $? "$label names $needle (said: $output)"
}

fresh_copy
output="$(preflight)"
verdict $? "the intact inventory passes ($output)"
[ -s "$work/inventory_preflight.txt" ]
verdict $? "the artifact is written under SP_WORK"
grep -q '^total 2[0-9][0-9]$' "$work/inventory_preflight.txt"
verdict $? "the artifact records a total count"
grep -qx 'upgrade:0.37.2' "$work/inventory_preflight.txt"
verdict $? "the artifact records the exact ordered list"

fresh_copy
rm "$repo/db/release_snapshots/1.15.2.image.sql.gz"
expect_fail "omitting a supported state's snapshot" "1.15.2"

fresh_copy
rm "$repo/db/release_snapshots/1.7.7.schemarb.sql.gz"
expect_fail "omitting a stored schema.rb variant" "1.7.7.schemarb"

fresh_copy
rm "$repo/db/release_snapshots/0.34.0.schemarb.sql.gz"
expect_fail "omitting a declared refusal's snapshot" "refused:0.34.0.schemarb"

fresh_copy
rm "$repo"/scripts/schema_parity/fixtures/1.15.2*
expect_fail "omitting a release's only fixtures" "1.15.2"

fresh_copy
ruby -rjson -e '
  path = ARGV[0]
  data = JSON.parse(File.read(path))
  state = data.fetch("states").find { _1.fetch("first_release") == "1.15.2" }
  state.fetch("data_added") << "20270101000000"
  File.write(path, JSON.pretty_generate(data))
' "$repo/db/release_migrations.json"
expect_fail "an unfixtured post-floor data_added version" "20270101000000"

fresh_copy
ruby -e '
  path = ARGV[0]
  prefix = "c40a98bf2edd9e43becbd6418b6e6fd8f580c20b\t1.7.7\t1.7.7\t"
  lines = File.readlines(path)
  lines.map! { |l| l.start_with?(prefix) ? l.sub("differs", "EXTRA\tdiffers") : l }
  File.write(path, lines.join)
' "$repo/db/release_snapshots/schemarb.tsv"
rm "$repo/db/release_snapshots/1.7.7.schemarb.sql.gz"
expect_fail "an extra schemarb.tsv column plus a deleted variant (reviewer repro)" "schemarb.tsv"

fresh_copy
rm "$repo/db/release_snapshots/schemarb.tsv"
output="$(preflight)"
status=$?
[ "$status" -ne 0 ]
verdict $? "a missing schemarb.tsv fails ($output)"
first_line="$(printf '%s\n' "$output" | head -n 1)"
case "$first_line" in
  "matrix inventory preflight:"*) pass "a missing schemarb.tsv reports itself first, not a raw backtrace" ;;
  *) flunk "a missing schemarb.tsv reports itself first, not a raw backtrace (said: $output)" ;;
esac

echo "$failures failed"
[ "$failures" -eq 0 ]
