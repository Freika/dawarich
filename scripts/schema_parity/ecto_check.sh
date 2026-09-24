#!/bin/sh
set -eu
check="${1:?usage: ecto_check.sh <check>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
out="$work/ecto"
mkdir -p "$out/ref" "$out/diffs" "$work/capture"
tmpd="$(mktemp -d "$work/.tmp.XXXXXX")"
run_id="$(basename "$tmpd" | tr -dc 'a-zA-Z0-9' | tr 'A-Z' 'a-z')"
rails_db="sp_r_$run_id"
ecto_db="sp_e_$run_id"
started="$(date -u +%s)"
trap 'release_harness "$rails_db" "$ecto_db"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

code_key="$(code_key)"
name="$(echo "$check" | tr ':+@~' '____')"
for part in schema ledger columns rows jobs; do rm -f "$out/diffs/$name.$part.diff"; done
kind="${check%%:*}"
arg="${check#*:}"
fixture=""
envfile=""
fixture_env=""
shift_to=0
holder_table=""
expect_unported=""
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
  case "$arg" in
    *--unported-*) expect_unported="${arg##*--unported-}" ;;
  esac
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

prepare() {
  recreate_db "$1"
  docker exec sp-db psql -U postgres -qc "ALTER DATABASE $1 SET timezone TO 'Pacific/Chatham'" >/dev/null
  case "$2" in
    none) ;;
    empty) rails_in "$1" runner 'ActiveRecord::Base.connection_pool.schema_migration.create_table; ActiveRecord::Base.connection_pool.internal_metadata.create_table' >/dev/null ;;
    *) restore_snapshot "$2" "$1" ;;
  esac
  [ -z "$3" ] || rails_in "$1" runner "ActiveRecord::Base.connection_pool.migration_context.migrate($3)" >/dev/null
  [ -z "$4" ] || query "$1" "INSERT INTO schema_migrations (version) VALUES ('$4')" >/dev/null
  [ "$shift_to" = 0 ] || query "$1" "SELECT setval(c.oid::regclass, $shift_to) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname = 'public'" >/dev/null
  [ -z "$fixture" ] || docker exec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$1" < "$fixture" >/dev/null
  [ "$kind" = refused ] || rails_in "$1" runner 'nil' >/dev/null
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
}

keep_ref() {
  rails_status="$(cat "$tmpd/rails.status")"
  if [ "$rails_status" = "${expect_status:-ok}" ]; then
    for part in sql out jobs schema ledger columns rows waits; do
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
  if [ "$(query "$ecto_db" "SELECT to_regclass('phoenix.release_migration_jobs') IS NOT NULL")" = t ]; then
    query "$ecto_db" 'SELECT json_build_array(job_class, arguments, wait_seconds) FROM phoenix.release_migration_jobs ORDER BY id' > "$tmpd/ecto.raw"
  fi
  canon_jobs "$tmpd/ecto.raw" "$tmpd/ecto.jobs"
  last_ecto="$(grep -v '^[[:space:]]*$' "$tmpd/ecto.out" | tail -n 1)"
}

compare() {
  rails_status="$(cat "$1.status")"
  ecto_status="$(cat "$tmpd/ecto.status")"
  if [ -n "$expect_unported" ]; then
    if [ "$rails_status" = ok ] && [ "$ecto_status" = "failed@$expect_unported" ] && grep -q 'has no Phoenix port yet' "$tmpd/ecto.out"; then
      echo "$check ok (unported@$expect_unported)"
      return 0
    fi
    fail "rails:$rails_status ecto:$ecto_status, expected unported@$expect_unported ($last_ecto)"
  fi
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
    rails_class="$(failure_class "$1.out")"
    ecto_class="$(failure_class "$tmpd/ecto.out")"
    [ "$rails_class" = "$ecto_class" ] || fail "both failed at ${rails_status#failed@}, rails with $rails_class, ecto with $ecto_class ($last_ecto)"
  fi
  if [ -n "$holder_table" ] && [ "$(cat "$1.waits")" != "$(cat "$tmpd/ecto.waits")" ]; then
    fail "lock attempts on $holder_table: rails $(cat "$1.waits"), ecto $(cat "$tmpd/ecto.waits")"
  fi
  diff_parts "$1" "$tmpd/ecto" schema ledger columns rows jobs
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
  ref="$out/ref/$name.$(key_of "$snapshot" "$fixture" "$envfile")-$code_key"
  if [ ! -s "$ref.status" ]; then
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
  ref="$out/ref/$name.$(key_of "$snapshot")-$code_key"
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
  diff_parts "$tmpd/before" "$tmpd/ecto" schema ledger columns rows jobs
  [ -z "$failures" ] || fail "changed$failures"
  echo "$check ok (refused below_floor $expect_refusal)"
}

run_fresh() {
  ref="$out/ref/$name.$(key_of "$root/db/schema.rb")-$code_key"
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
