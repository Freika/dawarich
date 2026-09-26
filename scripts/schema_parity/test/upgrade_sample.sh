#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-upgrade-sample.XXXXXX")"
repo="$scratch/repo"
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
  rm -rf "$repo" "$scratch/work"
  mkdir -p "$repo"
  cp -r "$root/db" "$repo/db"
  cp -r "$root/scripts" "$repo/scripts"
}

newest() {
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("states").last.fetch("first_release")' \
    "$repo/db/release_migrations.json"
}

add_state() {
  ruby -rjson -e '
    path = ARGV[0]
    data = JSON.parse(File.read(path))
    data.fetch("states") << { "first_release" => ARGV[1], "releases" => [ARGV[1]], "schema_added" => [],
                              "schema_removed" => [], "data_added" => [], "data_removed" => [] }
    File.write(path, JSON.pretty_generate(data))
  ' "$repo/db/release_migrations.json" "$1"
}

select_sample() {
  LANG=en_US.UTF-8 SP_WORK="$scratch/work" "$repo/scripts/schema_parity/ecto_prove.sh" --list > "$scratch/list.txt" \
    || return 2
  LANG=en_US.UTF-8 ruby "$repo/scripts/schema_parity/ci/upgrade_sample.rb" "$scratch/list.txt" 2>&1
}

expect_refusal() {
  label="$1"
  needle="$2"
  output="$(select_sample)"
  status=$?
  [ "$status" -ne 0 ]
  verdict $? "$label fails the selection (exit $status: $output)"
  contains "$output" "$needle"
  verdict $? "$label names $needle (said: $output)"
}

fresh_copy
latest="$(newest)"
expected="upgrade:0.37.2|upgrade:$latest|upgrade:1.0.1.schemarb|upgrade:0.37.2@20260108192905|"
output="$(select_sample)"
verdict $? "the intact list yields a sample ($output)"
[ "$(printf '%s\n' "$output" | tr '\n' '|')" = "$expected" ]
verdict $? "the sample is the floor, the newest state $latest, the 1.0.1 schema.rb variant and the interrupted upgrade"
missing=""
for check in $output; do grep -qxF "$check" "$scratch/list.txt" || missing="$missing $check"; done
[ -z "$missing" ]
verdict $? "every selected check is in ecto_prove.sh --list (missing:${missing:- none})"
[ "$(select_sample)" = "$output" ]
verdict $? "the selection is deterministic"

fresh_copy
rm "$repo/db/release_snapshots/1.0.1.schemarb.sql.gz"
expect_refusal "removing the 1.0.1 schema.rb snapshot" "upgrade:1.0.1.schemarb"

fresh_copy
mv "$repo/db/release_snapshots/1.0.1.schemarb.sql.gz" "$repo/db/release_snapshots/1.0.9.schemarb.sql.gz"
expect_refusal "renaming the 1.0.1 schema.rb snapshot" "upgrade:1.0.1.schemarb"

fresh_copy
rm "$repo/db/release_snapshots/0.37.2.image.sql.gz"
expect_refusal "removing the floor snapshot" "upgrade:0.37.2"
contains "$output" "upgrade:0.37.2@20260108192905"
verdict $? "the interrupted upgrade loses its snapshot with the floor (said: $output)"

fresh_copy
rm "$repo/db/release_snapshots/$latest.image.sql.gz"
expect_refusal "removing the newest state's snapshot" "upgrade:$latest"

fresh_copy
sed "s/'upgrade:0.37.2@20260108192905', //" "$root/scripts/schema_parity/list_checks.rb" \
  > "$repo/scripts/schema_parity/list_checks.rb"
! grep -q '0.37.2@20260108192905' "$repo/scripts/schema_parity/list_checks.rb"
verdict $? "the probe removed the interrupted upgrade from list_checks.rb"
expect_refusal "dropping the interrupted upgrade from the list" "upgrade:0.37.2@20260108192905"

fresh_copy
: > "$scratch/list.txt"
output="$(LANG=en_US.UTF-8 ruby "$repo/scripts/schema_parity/ci/upgrade_sample.rb" "$scratch/list.txt" 2>&1)"
[ $? -ne 0 ] && contains "$output" "upgrade:0.37.2" && contains "$output" "upgrade:1.0.1.schemarb"
verdict $? "an empty list refuses the whole sample (said: $output)"

fresh_copy
add_state 9.9.9
: > "$repo/db/release_snapshots/9.9.9.image.sql.gz"
output="$(select_sample)"
verdict $? "a new latest release with its snapshot still yields a sample ($output)"
[ "$(printf '%s\n' "$output" | tr '\n' '|')" = \
  "upgrade:0.37.2|upgrade:9.9.9|upgrade:1.0.1.schemarb|upgrade:0.37.2@20260108192905|" ]
verdict $? "the sample advances to the new latest release upgrade:9.9.9"

fresh_copy
add_state 9.9.9
expect_refusal "a new latest release without its snapshot" "upgrade:9.9.9"

leg="$scratch/leg"
prove_leg() {
  rm -rf "$leg"
  mkdir -p "$leg/nightly" "$leg/ecto"
  printf '%s\n' upgrade:0.37.2 "upgrade:$latest" upgrade:1.0.1.schemarb upgrade:0.37.2@20260108192905 \
    > "$leg/nightly/list.txt"
  printf 'started=100\nexit=0\nfinished=160\nrefs_reused=0\nrefs_computed=4\n' > "$leg/nightly/proof.env"
  sed "s/\$/ ok/" "$leg/nightly/list.txt" > "$leg/ecto/summary.txt"
}
verify_leg() {
  LANG=en_US.UTF-8 RUN_URL=x ruby "$root/scripts/schema_parity/ci/nightly_report.rb" leg "$leg" 2>&1
}

prove_leg
output="$(verify_leg)"
verdict $? "four ok lines pass the sample's summary check ($output)"

prove_leg
sed -i.bak "2s/ ok\$/ ok (unported@20260720170000)/" "$leg/ecto/summary.txt"
output="$(verify_leg)"
[ $? -ne 0 ] && contains "$output" "upgrade:$latest: expected 'ok', actual 'ok (unported@20260720170000)'"
verdict $? "an unported result on a sampled upgrade fails the summary check ($output)"

prove_leg
sed -i.bak '3d' "$leg/ecto/summary.txt"
output="$(verify_leg)"
[ $? -ne 0 ] && contains "$output" "upgrade:1.0.1.schemarb: expected 'ok', actual: no line"
verdict $? "a missing summary line fails the summary check ($output)"

echo "$failures failed"
[ "$failures" -eq 0 ]
