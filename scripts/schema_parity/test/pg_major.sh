#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
infra="$root/scripts/schema_parity/infra.sh"
mkdir -p "$root/tmp/schema_parity"
scratch="$(mktemp -d "$root/tmp/schema_parity/.test.XXXXXX")"
image_snapshot="$root/db/release_snapshots/0.37.2.image.sql.gz"
schemarb_snapshot="$root/db/release_snapshots/1.7.7.schemarb.sql.gz"
exact='SET transaction_timeout = 0;'
failures=0

on() {
  server="$1"
  shift
  env SP_DB_CONTAINER="sp-test-db-$server" SP_DB_PORT="557$server" SP_REDIS_CONTAINER=sp-test-redis \
    SP_REDIS_PORT=56717 SP_NETWORK=sp-test "$@"
}

teardown() {
  on 14 env SP_PG_MAJOR=14 "$infra" down
  on 17 env SP_PG_MAJOR=17 "$infra" down
}

trap 'teardown; rm -rf "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

rejected_with() {
  label="$1"
  expected="$2"
  shift 2
  if output="$("$@" 2>&1)"; then
    flunk "$label (exited 0)"
  elif contains "$output" "$expected"; then
    pass "$label"
  else
    flunk "$label (said: $output)"
  fi
}

in_harness() {
  server="$1"
  major="$2"
  script="$3"
  shift 3
  mkdir -p "$scratch/$server"
  on "$server" env SP_PG_MAJOR="$major" root="$root" tmpd="$scratch/$server" sh -c "set -eu
    . \"\$root/scripts/schema_parity/lib.sh\"
    $script" sh "$@"
}

restore() {
  in_harness "$1" "$1" 'recreate_db "$1"
    restore_snapshot "$2" "$1"
    dexec "$db_container" psql -U postgres -d "$1" -Atc "SELECT count(*) FROM schema_migrations"' "$2" "$3"
}

code_key_for() {
  env "$@" root="$root" tmpd="$scratch" sh -c '. "$root/scripts/schema_parity/lib.sh"
    . "$root/scripts/schema_parity/ecto_lib.sh"
    code_key'
}

teardown
before="$(git -C "$root" hash-object --no-filters "$image_snapshot" "$schemarb_snapshot")"

for bad in 15 13 16 '' abc 17.5; do
  rejected_with "SP_PG_MAJOR='$bad' is rejected" "SP_PG_MAJOR must be 14 or 17" on 14 env SP_PG_MAJOR="$bad" "$infra" up
done
docker inspect sp-test-db-14 >/dev/null 2>&1
verdict "$((1 - $?))" "a rejected SP_PG_MAJOR starts no container"

on 14 env SP_PG_MAJOR=14 "$infra" up
verdict $? "SP_PG_MAJOR=14 starts a server"
on 17 env -u SP_PG_MAJOR "$infra" up
verdict $? "an unset SP_PG_MAJOR starts a server"
for major in 14 17; do
  image="$(docker inspect -f '{{.Config.Image}}' "sp-test-db-$major" 2>&1)"
  echo "$image" | grep -Eqx "postgis/postgis:$major-3\.5@sha256:[0-9a-f]{64}"
  verdict $? "server $major runs a digest-pinned postgis/postgis:$major-3.5 image ($image)"
  version="$(docker exec "sp-test-db-$major" psql -U postgres -Atc 'SHOW server_version_num' 2>&1)"
  echo "$version" | grep -Eqx "$major[0-9]{4}"
  verdict $? "server $major reports server_version_num $version"
  published="$(docker port "sp-test-db-$major" 5432 2>&1)"
  [ "$published" = "127.0.0.1:557$major" ]
  verdict $? "server $major listens on the SP_DB_PORT override ($published)"
done
on 17 env SP_PG_MAJOR=17 "$infra" up
verdict $? "SP_PG_MAJOR=17 accepts the running 17 server"
rejected_with "an unset SP_PG_MAJOR refuses a running 14 server" "runs PostgreSQL 14" on 14 env -u SP_PG_MAJOR "$infra" up
rejected_with "SP_PG_MAJOR=14 refuses a running 17 server" "runs PostgreSQL 17" on 17 env SP_PG_MAJOR=14 "$infra" up
rejected_with "ecto_prove.sh refuses a server of another major" "runs PostgreSQL 17" \
  on 17 env SP_PG_MAJOR=14 "$root/scripts/schema_parity/ecto_prove.sh" upgrade:0.37.2

key14="$(code_key_for SP_PG_MAJOR=14)"
key17="$(code_key_for SP_PG_MAJOR=17)"
key_default="$(code_key_for -u SP_PG_MAJOR)"
[ -n "$key14" ] && [ "$key14" != "$key17" ] && [ "$key_default" = "$key17" ]
verdict $? "the Rails reference key depends on the major, and defaults to 17"

docker exec sp-test-db-14 createdb -U postgres sp_test_raw
gunzip -c "$image_snapshot" | docker exec -i sp-test-db-14 psql -U postgres -q -v ON_ERROR_STOP=1 -d sp_test_raw >/dev/null 2> "$scratch/raw.err"
raw_status=$?
[ "$raw_status" -ne 0 ] && grep -q 'unrecognized configuration parameter "transaction_timeout"' "$scratch/raw.err"
verdict $? "the unfiltered 0.37.2 dump fails on PostgreSQL 14 under ON_ERROR_STOP ($(head -n 1 "$scratch/raw.err"))"

for snapshot in "$image_snapshot" "$schemarb_snapshot"; do
  name="$(basename "$snapshot")"
  filtered="$(gunzip -c "$snapshot" | grep -vxF "$exact" | git -C "$root" hash-object --no-filters --stdin)"
  ledger="$(restore 14 sp_test_restore "$snapshot" 2> "$scratch/restore.err")"
  verdict $? "$name restores into PostgreSQL 14 ($(tail -n 1 "$scratch/restore.err"))"
  [ "${ledger:-0}" -gt 0 ]
  verdict $? "$name has its ledger on PostgreSQL 14 ($ledger versions)"
  grep -qF "without its 2 '$exact' lines: $filtered" "$scratch/restore.err"
  verdict $? "$name records the count and the filtered-input checksum $filtered"
  ledger="$(restore 17 sp_test_restore "$snapshot" 2> "$scratch/restore.err")"
  verdict $? "$name restores into PostgreSQL 17 ($(tail -n 1 "$scratch/restore.err"))"
  [ "${ledger:-0}" -gt 0 ] && ! grep -q transaction_timeout "$scratch/restore.err" && gunzip -c "$snapshot" | cmp -s - "$scratch/17/restore.sql"
  verdict $? "$name reaches PostgreSQL 17 byte for byte ($ledger versions)"
done

gunzip -c "$image_snapshot" > "$scratch/extra.sql"
echo "$exact" >> "$scratch/extra.sql"
gzip -n "$scratch/extra.sql"
rejected_with "a third '$exact' is refused before psql runs" "found 3 for 2 pg_dump preambles" \
  restore 14 sp_test_extra "$scratch/extra.sql.gz"
gunzip -c "$image_snapshot" | awk -v exact="$exact" '{ print } $0 == exact && !done { print "SET transaction_timeout = 5;"; done = 1 }' \
  > "$scratch/variant.sql"
gzip -n "$scratch/variant.sql"
rejected_with "any other transaction_timeout statement still fails on PostgreSQL 14" \
  'unrecognized configuration parameter "transaction_timeout"' restore 14 sp_test_variant "$scratch/variant.sql.gz"

after="$(git -C "$root" hash-object --no-filters "$image_snapshot" "$schemarb_snapshot")"
[ "$before" = "$after" ] && git -C "$root" diff --quiet -- "$image_snapshot" "$schemarb_snapshot"
verdict $? "the compressed snapshots are unchanged"

echo "$failures failed"
[ "$failures" -eq 0 ]
