#!/bin/sh
set -eu
exec 3>&1
check="${1:?usage: ecto_check.sh <check>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
. "$root/scripts/schema_parity/ecto_template.sh"
out="$work/ecto"
mkdir -p "$out/ref" "$out/diffs" "$work/capture"
tmpd="$(mktemp -d "$work/.tmp.XXXXXX")"
run_id="$$x$(basename "$tmpd" | tr -dc 'a-zA-Z0-9' | tr 'A-Z' 'a-z')"
rails_db="sp_r_$run_id"
ecto_db="sp_e_$run_id"
started="$(date -u +%s)"
trap 'release_harness "$rails_db" "$ecto_db"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if dotenv="$(local_dotenv)"; then
  echo "$check FAIL refusing to run: $dotenv exists and dotenv would load it into the Rails side only"
  exit 2
fi
list_checks > /dev/null 2> "$tmpd/checks.err" || { echo "$check FAIL $(tr '\n' ' ' < "$tmpd/checks.err")"; exit 2; }
code_key="$(code_key)" || fail "could not hash the Rails inputs"
name="$(echo "$check" | tr ':+@~' '____')"
for part in $parts; do rm -f "$out/diffs/$name.$part.diff"; done
kind="${check%%:*}"
arg="${check#*:}"
fixture=""
envfile=""
fixture_env=""
shift_to=0
holder_table=""
expect_job=""
expect_refusal=""
read -r expect_status expect_detail <<EOF
$(awk -F '\t' -v c="$check" '$1 == c { print $2, $3 }' "$expectations")
EOF
case "$arg" in
  *~shifted) shift_to=100000; arg="${arg%~shifted}" ;;
esac
if [ "$kind" = rows ]; then
  fixture="$root/scripts/schema_parity/fixtures/$arg.sql"
  [ -f "$fixture" ] || fail "no fixture $fixture"
  envfile="${fixture%.sql}.env"
  [ ! -f "$envfile" ] || fixture_env="$(cat "$envfile")"
  arg="${arg%%--*}"
fi
if [ "$kind" = contended ]; then
  holder_table="${arg#*:}"
  arg="${arg%%:*}"
  [ -n "$expect_status" ] || fail "no declared expectation for this contended check in ecto_expectations.tsv"
fi
if [ "$kind" = refused ]; then
  [ "$expect_status" = refused ] && [ -n "$expect_detail" ] \
    || fail "no declared expectation for this refusal check in ecto_expectations.tsv"
  expect_refusal="$expect_detail"
  expect_status=""
elif [ -n "$expect_detail" ] && [ "$expect_detail" != - ]; then
  expect_job="$expect_detail"
fi

rails_in() {
  db="$1"
  shift
  (cd "$root" && scrubbed $rails_env $fixture_env DATABASE_NAME="$db" bin/rails "$@")
}

ecto_in() {
  db="$1"
  shift
  (cd "$root/app-phoenix" && scrubbed $ecto_env $fixture_env PHOENIX_TEST_DATABASE="$db" mix dawarich.release_migrate "$@")
}

rails_side() {
  if rails_in "$rails_db" runner scripts/schema_parity/rails_reference.rb "$1" "$tmpd/rails" > "$tmpd/rails.out" 2>&1; then
    echo ok > "$tmpd/rails.status"
  else
    echo "failed@$(sed -n 's/^== \([0-9][0-9]*\) .*: migrating.*/\1/p' "$tmpd/rails.out" | tail -n 1)" > "$tmpd/rails.status"
  fi
  record "$rails_db" "$tmpd/rails"
  [ -f "$tmpd/rails.jobs" ] || fail "rails_reference.rb wrote no jobs file ($(tail -n 1 "$tmpd/rails.out"))"
  canon_jobs "$tmpd/rails.jobs" "$tmpd/rails.canon"
  mv "$tmpd/rails.canon" "$tmpd/rails.jobs"
  [ ! -f "$tmpd/rails.message" ] || canon_message "$tmpd/rails.message" "$tmpd/rails.canon"
  [ ! -f "$tmpd/rails.message" ] || mv "$tmpd/rails.canon" "$tmpd/rails.message"
}

keep_ref() {
  rails_status="$(cat "$tmpd/rails.status")"
  if [ -z "$holder_table" ] && [ "$rails_status" = "${expect_status:-ok}" ]; then
    for part in sql out failure message $parts; do
      [ ! -f "$tmpd/rails.$part" ] || mv "$tmpd/rails.$part" "$1.$part"
    done
    mv "$tmpd/rails.status" "$1.status"
  else
    ref="$tmpd/rails"
  fi
}

ecto_side() {
  if ecto_in "$ecto_db" "$@" > "$tmpd/ecto.out" 2>&1; then
    echo ok > "$tmpd/ecto.status"
  else
    echo "failed@$(sed -n 's/.*failed [^ ]* \([0-9][0-9]*\):.*/\1/p' "$tmpd/ecto.out" | tail -n 1)" > "$tmpd/ecto.status"
  fi
  record "$ecto_db" "$tmpd/ecto"
  : > "$tmpd/ecto.raw"
  has_jobs="$(query "$ecto_db" "SELECT to_regclass('phoenix.release_migration_jobs') IS NOT NULL")" || fail "could not look for the job table of $ecto_db"
  if [ "$has_jobs" = t ]; then
    query "$ecto_db" 'SELECT json_build_array(job_class, arguments, wait_seconds) FROM phoenix.release_migration_jobs ORDER BY id' > "$tmpd/ecto.raw"
  fi
  canon_jobs "$tmpd/ecto.raw" "$tmpd/ecto.jobs"
  last_ecto="$(grep -v '^[[:space:]]*$' "$tmpd/ecto.out" | tail -n 1)"
  failed_step='.*failed [^ ]* [0-9][0-9]*: \*\* (\([^)]*\)) \(.*\)'
  sed -n "s/$failed_step/\\2/p" "$tmpd/ecto.out" | tail -n 1 > "$tmpd/ecto.raw"
  canon_message "$tmpd/ecto.raw" "$tmpd/ecto.message"
}

compare() {
  rails_status="$(cat "$1.status")"
  ecto_status="$(cat "$tmpd/ecto.status")"
  if [ "$rails_status" != "$ecto_status" ] || [ "$rails_status" = "failed@" ]; then
    fail "rails:$rails_status ecto:$ecto_status ($last_ecto)"
  fi
  if [ -n "$expect_status" ] && [ "$rails_status" != "$expect_status" ]; then
    fail "rails:$rails_status, expected $expect_status (ecto_expectations.tsv)"
  fi
  if [ -n "$expect_job" ] && ! grep -qF "\"$expect_job\"" "$1.jobs"; then
    fail "contention had no effect: no $expect_job"
  fi
  if [ "$rails_status" != ok ]; then
    rails_class="$(cat "$1.failure" 2>/dev/null || echo none)"
    ecto_class="$(failure_class "$tmpd/ecto.out")"
    [ -z "$holder_table" ] || [ "$rails_class" != none ] || fail "contended failure without a concrete failure class ($last_ecto)"
    [ "$rails_class" = "$ecto_class" ] || fail "both failed at ${rails_status#failed@}, rails with $rails_class, ecto with $ecto_class ($last_ecto)"
    [ "$rails_class" != none ] || cmp -s "$1.message" "$tmpd/ecto.message" \
      || fail "both failed at ${rails_status#failed@} with no Postgres error: rails \"$(cat "$1.message" 2>/dev/null)\", ecto \"$(cat "$tmpd/ecto.message")\""
  fi
  if [ -n "$holder_table" ] && [ "$(cat "$1.waits")" -lt 1 ]; then
    fail "contention had no effect: rails recorded no lock wait on $holder_table"
  fi
  if [ -n "$holder_table" ] && [ "$(cat "$1.waits")" != "$(cat "$tmpd/ecto.waits")" ]; then
    fail "lock attempts on $holder_table: rails $(cat "$1.waits"), ecto $(cat "$tmpd/ecto.waits")"
  fi
  diff_parts "$1" "$tmpd/ecto" $parts
  [ -z "$failures" ] || fail "${failures# }"
  if [ "$rails_status" = ok ]; then echo "$check ok"; else echo "$check ok ($rails_status)"; fi
}

resolve_label() {
  upto=""
  extra=""
  case "$1" in
    *@*) snapshot="$(snapshot_of "${1%%@*}")" || fail "no snapshot for ${1%%@*}"; upto="${1#*@}" ;;
    *+*) snapshot="$(snapshot_of "${1%%+*}")" || fail "no snapshot for ${1%%+*}"; extra="${1#*+}" ;;
    *.schemarb) snapshot="$snapshots/$1.sql.gz" ;;
    *) snapshot="$(snapshot_of "$1")" || fail "no snapshot for $1" ;;
  esac
  [ -f "$snapshot" ] || fail "no snapshot $snapshot"
}

run_release() {
  release="$1"
  prev="$(ruby -rjson -e '
    states = JSON.parse(File.read(ARGV[0])).fetch("states").map { _1.fetch("first_release") }
    index = ARGV[1] == "unreleased" ? states.size : states.index(ARGV[1])
    abort "no state #{ARGV[1]} in db/release_migrations.json" unless index
    puts states[index - 1] if index.positive?' "$root/db/release_migrations.json" "$release")" || fail "no state $release"
  snapshot=empty
  [ -z "$prev" ] || snapshot="$(snapshot_of "$prev")" || fail "no snapshot for $prev"
  key="$(key_of "$snapshot" "$fixture" "$envfile")" || fail "could not hash the inputs of $check"
  ref="$out/ref/$name.$key-$code_key"
  if [ -n "$holder_table" ] || [ ! -s "$ref.status" ]; then
    prepare "$rails_db" "$snapshot" "" ""
    hold "$rails_db"
    rails_side "$release"
    unhold "$rails_db" "$tmpd/rails"
    keep_ref "$ref"
  fi
  [ "$kind" != step ] || cp "$ref.sql" "$work/capture/$release.sql"
  prepare "$ecto_db" "$snapshot" "" ""
  hold "$ecto_db"
  ecto_side --only "$release"
  unhold "$ecto_db" "$tmpd/ecto"
  compare "$ref"
}

run_upgrade() {
  resolve_label "$1"
  key="$(key_of "$snapshot")" || fail "could not hash the inputs of $check"
  ref="$out/ref/$name.$key-$code_key"
  if [ ! -s "$ref.status" ]; then
    prepare "$rails_db" "$snapshot" "$upto" "$extra"
    rails_side all
    keep_ref "$ref"
  fi
  prepare "$ecto_db" "$snapshot" "$upto" "$extra"
  ecto_side
  compare "$ref"
}

run_refused() {
  resolve_label "$1"
  prepare "$ecto_db" "$snapshot" "$upto" "$extra"
  record "$ecto_db" "$tmpd/before"
  : > "$tmpd/before.jobs"
  ecto_side
  [ "$(cat "$tmpd/ecto.status")" != ok ] || fail "the Ecto side exited 0, expected refused below_floor $expect_refusal ($last_ecto)"
  case "$last_ecto" in
    *"refused: this database has not reached Dawarich $expect_refusal,"*) ;;
    *) fail "expected refused below_floor $expect_refusal ($last_ecto)" ;;
  esac
  diff_parts "$tmpd/before" "$tmpd/ecto" $parts
  [ -z "$failures" ] || fail "changed$failures"
  echo "$check ok (refused below_floor $expect_refusal)"
}

run_fresh() {
  key="$(key_of "$root/db/schema.rb")" || fail "could not hash the inputs of $check"
  ref="$out/ref/$name.$key-$code_key"
  if [ ! -s "$ref.status" ]; then
    prepare "$rails_db" "$1" "" ""
    rails_side schema
    keep_ref "$ref"
  fi
  prepare "$ecto_db" "$1" "" ""
  ecto_side
  compare "$ref"
}

case "$check" in
  fresh) run_fresh none ;;
  fresh:empty) run_fresh empty ;;
  step:* | rows:* | contended:*) run_release "$arg" ;;
  upgrade:*) run_upgrade "$arg" ;;
  refused:*) run_refused "$arg" ;;
  *) echo "$check FAIL unknown check"; exit 2 ;;
esac
