#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
lib="$root/scripts/schema_parity"
infra="$lib/infra.sh"
prove="$lib/ecto_prove.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-pg-major.XXXXXX")"
work="$scratch/work"
image_snapshot="$root/db/release_snapshots/0.37.2.image.sql.gz"
schemarb_snapshot="$root/db/release_snapshots/1.7.7.schemarb.sql.gz"
checkout_summary="$root/tmp/schema_parity/ecto/summary.txt"
exact='SET transaction_timeout = 0;'
run="sp-test-$$"
failures=0

port_free() {
  perl -MIO::Socket::INET -e 'IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], Proto => "tcp", Listen => 1) or exit 1' "$1"
}

free_port() {
  candidate="$1"
  until port_free "$candidate"; do candidate=$((candidate + 1)); done
  echo "$candidate"
}

port14="$(free_port $((55700 + $$ % 100 * 3)))"
port17="$(free_port $((port14 + 1)))"
redis_port="$(free_port $((port17 + 1)))"

on() {
  case "$1" in
    14) port="$port14" ;;
    17) port="$port17" ;;
  esac
  server="$1"
  shift
  env SP_DB_CONTAINER="$run-db-$server" SP_DB_PORT="$port" SP_REDIS_CONTAINER="$run-redis" \
    SP_REDIS_PORT="$redis_port" SP_NETWORK="$run" SP_WORK="$work" "$@"
}

bare() {
  (
    unset SP_DB_CONTAINER SP_DB_PORT SP_REDIS_CONTAINER SP_REDIS_PORT SP_NETWORK SP_PG_MAJOR
    "$@"
  )
}

without_major() {
  (
    unset SP_PG_MAJOR
    "$@"
  )
}

mkdir -p "$scratch/bin" "$scratch/grepbin" "$scratch/gitbin"
cat > "$scratch/bin/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_DOCKER_LOG"
case "$*" in
  *"SHOW server_version_num"*)
    [ -z "${FAKE_DOCKER_HANG:-}" ] || exec sleep 30
    echo "${FAKE_DOCKER_VERSION:-170005}"
    exit 0
    ;;
esac
[ -z "${FAKE_DOCKER_ECHO:-}" ] || { echo "$*"; exit 0; }
exit 1
EOF
printf '#!/bin/sh\ncase "$1" in -c*) echo "grep: injected failure" >&2; exit 2 ;; esac\nexec %s "$@"\n' \
  "$(command -v grep)" > "$scratch/grepbin/grep"
printf '#!/bin/sh\ncase "$*" in *hash-object*) echo "git: injected failure" >&2; exit 1 ;; esac\nexec %s "$@"\n' \
  "$(command -v git)" > "$scratch/gitbin/git"
chmod +x "$scratch/bin/docker" "$scratch/grepbin/grep" "$scratch/gitbin/git"

faked() {
  : > "$scratch/docker.log"
  (
    PATH="$scratch/bin:$PATH"
    FAKE_DOCKER_LOG="$scratch/docker.log"
    export FAKE_DOCKER_LOG
    "$@"
  )
}

docker_calls() {
  wc -l < "$scratch/docker.log" | tr -d ' '
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

refused() {
  label="$1"
  code="$2"
  expected="$3"
  shift 3
  output="$("$@" 2>&1)"
  status=$?
  if [ "$status" -ne "$code" ]; then
    flunk "$label (exit $status, not $code: $output)"
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

summary_state() {
  if [ -f "$checkout_summary" ]; then cksum < "$checkout_summary"; else echo absent; fi
}

teardown
before="$(git -C "$root" hash-object --no-filters "$image_snapshot" "$schemarb_snapshot")"
summary_before="$(summary_state)"

for bad in 15 13 16 '' abc 17.5; do
  refused "SP_PG_MAJOR='$bad' is rejected" 2 "SP_PG_MAJOR must be 14 or 17" faked on 14 env SP_PG_MAJOR="$bad" "$infra" up
  [ "$(docker_calls)" = 0 ]
  verdict $? "SP_PG_MAJOR='$bad' reaches no container"
done

refused "SP_REDIS_CONTAINER alone is refused by infra.sh down" 2 \
  "missing or empty: SP_DB_CONTAINER SP_DB_PORT SP_REDIS_PORT SP_NETWORK" \
  bare faked env SP_REDIS_CONTAINER="$run-redis" "$infra" down
[ "$(docker_calls)" = 0 ]
verdict $? "the partial set removes nothing (no docker call)"
refused "SP_DB_CONTAINER alone is refused by ecto_prove.sh" 2 "missing or empty: SP_DB_PORT SP_REDIS_CONTAINER" \
  bare faked env SP_DB_CONTAINER="$run-db-14" "$prove" upgrade:0.37.2
[ "$(docker_calls)" = 0 ]
verdict $? "the partial set reaches no container"
refused "an empty SP_NETWORK is refused" 2 "missing or empty: SP_NETWORK" faked on 14 env SP_NETWORK= "$infra" up
[ "$(docker_calls)" = 0 ]
verdict $? "the empty override reaches no container"

for writer in "snapshot.sh 0.37.2" snapshot_all.sh schemarb_all.sh baseline.sh "compare.sh 0.37.2" compare_all.sh; do
  set -- $writer
  writer_script="$1"
  shift
  refused "$writer_script refuses SP_PG_MAJOR=14" 2 "$writer_script runs on PostgreSQL 17 only" \
    faked on 14 env SP_PG_MAJOR=14 "$lib/$writer_script" "$@"
  [ "$(docker_calls)" = 0 ]
  verdict $? "$writer_script under SP_PG_MAJOR=14 reaches no container"
  refused "$writer_script refuses a PostgreSQL 14 server" 1 "runs PostgreSQL 14, but SP_PG_MAJOR selects 17" \
    faked on 17 env SP_PG_MAJOR=17 FAKE_DOCKER_VERSION=140018 "$lib/$writer_script" "$@"
  [ "$(docker_calls)" = 1 ]
  verdict $? "$writer_script only read the server version ($(docker_calls) docker calls)"
done
output="$(faked on 17 env SP_PG_MAJOR=17 "$lib/snapshot.sh" 0.37.2 2>&1)"
verdict $? "snapshot.sh accepts a PostgreSQL 17 server ($output)"

rm -rf "$work"
refused "a hung version check aborts ecto_prove.sh" 2 "timed out reading the PostgreSQL version" \
  faked on 17 env SP_PG_MAJOR=17 SP_EXEC_TIMEOUT=1 FAKE_DOCKER_HANG=1 "$prove" upgrade:0.37.2
[ "$(cat "$work/ecto/summary.txt" 2>&1)" = "ABORTED timed out reading the PostgreSQL version of $run-db-17" ]
verdict $? "the timeout leaves its ABORTED line ($(cat "$work/ecto/summary.txt" 2>&1))"

restore_with() {
  (
    PATH="$scratch/$1:$PATH"
    FAKE_DOCKER_ECHO=1
    export FAKE_DOCKER_ECHO
    faked in_harness 14 14 'restore_snapshot "$1" sp_test_fake' "$image_snapshot"
  )
}
for fake in grepbin gitbin; do
  refused "a failing ${fake%bin} fails the PostgreSQL 14 restore" 1 "injected failure" restore_with "$fake"
  [ "$(docker_calls)" = 0 ] && ! contains "$output" "restoring"
  verdict $? "the failing ${fake%bin} stops the restore before psql ($(docker_calls) docker calls)"
done

dexec_line="$(faked on 17 env SP_PG_MAJOR=17 FAKE_DOCKER_ECHO=1 root="$root" sh -c '. "$root/scripts/schema_parity/lib.sh"
  dexec -i -e PGTZ=UTC "$db_container" echo "$db_container"')"
[ "$dexec_line" = "exec -i -e PGTZ=UTC $run-db-17 timeout 300 echo $run-db-17" ]
verdict $? "dexec adds timeout after the container argument only ($dexec_line)"

on 14 env SP_PG_MAJOR=14 "$infra" up
verdict $? "SP_PG_MAJOR=14 starts a server"
without_major on 17 "$infra" up
verdict $? "an unset SP_PG_MAJOR starts a server"
for major in 14 17; do
  image="$(docker inspect -f '{{.Config.Image}}' "$run-db-$major" 2>&1)"
  echo "$image" | grep -Eqx "postgis/postgis:$major-3\.5@sha256:[0-9a-f]{64}"
  verdict $? "server $major runs a digest-pinned postgis/postgis:$major-3.5 image ($image)"
  version="$(docker exec "$run-db-$major" psql -U postgres -Atc 'SHOW server_version_num' 2>&1)"
  echo "$version" | grep -Eqx "$major[0-9]{4}"
  verdict $? "server $major reports server_version_num $version"
  published="$(docker port "$run-db-$major" 5432 2>&1)"
  expected_port="$port14"
  [ "$major" = 14 ] || expected_port="$port17"
  [ "$published" = "127.0.0.1:$expected_port" ]
  verdict $? "server $major listens on the SP_DB_PORT override ($published)"
  ! port_free "$expected_port"
  verdict $? "the free-port probe sees port $expected_port as taken"
done
on 17 env SP_PG_MAJOR=17 "$infra" up
verdict $? "SP_PG_MAJOR=17 accepts the running 17 server"
refused "a reused server on another port is refused" 1 "not 127.0.0.1:$port17" \
  on 14 env SP_PG_MAJOR=14 SP_DB_PORT="$port17" "$infra" up
refused "a reused Redis on another port is refused" 1 "not 127.0.0.1:$port17" \
  on 14 env SP_PG_MAJOR=14 SP_REDIS_PORT="$port17" "$infra" up
refused "an unset SP_PG_MAJOR refuses a running 14 server" 1 "runs PostgreSQL 14" without_major on 14 "$infra" up
refused "SP_PG_MAJOR=14 refuses a running 17 server" 1 "runs PostgreSQL 17" on 17 env SP_PG_MAJOR=14 "$infra" up
rm -rf "$work"
refused "ecto_prove.sh refuses a server of another major" 2 "runs PostgreSQL 17" \
  on 17 env SP_PG_MAJOR=14 "$prove" upgrade:0.37.2
[ "$(cat "$work/ecto/summary.txt" 2>&1)" = "ABORTED $run-db-17 runs PostgreSQL 17, but SP_PG_MAJOR selects 14" ]
verdict $? "the refusal lands in SP_WORK ($(cat "$work/ecto/summary.txt" 2>&1))"
[ "$(summary_state)" = "$summary_before" ]
verdict $? "the checkout's own summary is untouched"

key14="$(code_key_for SP_PG_MAJOR=14)"
key17="$(code_key_for SP_PG_MAJOR=17)"
key_default="$(without_major code_key_for)"
[ -n "$key14" ] && [ "$key14" != "$key17" ] && [ "$key_default" = "$key17" ]
verdict $? "the Rails reference key depends on the major, and defaults to 17"

docker exec "$run-db-14" createdb -U postgres sp_test_raw
gunzip -c "$image_snapshot" | docker exec -i "$run-db-14" psql -U postgres -q -v ON_ERROR_STOP=1 -d sp_test_raw >/dev/null 2> "$scratch/raw.err"
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
refused "a third '$exact' is refused before psql runs" 1 "found 3 for 2 pg_dump preambles" \
  restore 14 sp_test_extra "$scratch/extra.sql.gz"
gunzip -c "$image_snapshot" | awk -v exact="$exact" '{ print } $0 == exact && !done { print "SET transaction_timeout = 5;"; done = 1 }' \
  > "$scratch/variant.sql"
gzip -n "$scratch/variant.sql"
refused "any other transaction_timeout statement still fails on PostgreSQL 14" 3 \
  'unrecognized configuration parameter "transaction_timeout"' restore 14 sp_test_variant "$scratch/variant.sql.gz"

after="$(git -C "$root" hash-object --no-filters "$image_snapshot" "$schemarb_snapshot")"
[ "$before" = "$after" ] && git -C "$root" diff --quiet -- "$image_snapshot" "$schemarb_snapshot"
verdict $? "the compressed snapshots are unchanged"

echo "$failures failed"
[ "$failures" -eq 0 ]
