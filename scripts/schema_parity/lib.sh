pg_major="${SP_PG_MAJOR-17}"
case "$pg_major" in
  14 | 17) ;;
  *) echo "SP_PG_MAJOR must be 14 or 17, got '$pg_major'" >&2; exit 2 ;;
esac
sp_set=0
sp_missing=""
for sp_var in SP_DB_CONTAINER SP_DB_PORT SP_REDIS_CONTAINER SP_REDIS_PORT SP_NETWORK; do
  eval "sp_flag=\${$sp_var+set} sp_value=\${$sp_var-}"
  [ -z "$sp_flag" ] || sp_set=$((sp_set + 1))
  [ -n "$sp_value" ] || sp_missing="$sp_missing $sp_var"
done
if [ "$sp_set" -gt 0 ] && [ -n "$sp_missing" ]; then
  echo "set all of SP_DB_CONTAINER, SP_DB_PORT, SP_REDIS_CONTAINER, SP_REDIS_PORT and SP_NETWORK, or none; missing or empty:$sp_missing" >&2
  exit 2
fi
db_container="${SP_DB_CONTAINER:-sp-db}"
redis_container="${SP_REDIS_CONTAINER:-sp-redis}"
network="${SP_NETWORK:-schema-parity}"
db_port="${SP_DB_PORT:-55532}"
redis_port="${SP_REDIS_PORT:-56479}"
work="${SP_WORK:-$root/tmp/schema_parity}"
snapshots="$root/db/release_snapshots"
rails_env="DATABASE_HOST=127.0.0.1 DATABASE_PORT=$db_port DATABASE_USERNAME=postgres DATABASE_PASSWORD=parity REDIS_URL=redis://127.0.0.1:$redis_port SCHEMA=$work/throwaway_schema.rb RAILS_ENV=development"
exec_timeout="${SP_EXEC_TIMEOUT:-300}"

exec_timed_out() {
  echo "timed out: $1" >&2
  [ -z "${tmpd:-}" ] || echo "$1" > "$tmpd/timed_out"
  [ -n "${releasing:-}" ] || kill -TERM $$
  exit 124
}

dexec_for() {
  dexec_limit="$1"
  shift
  dexec_n=$#
  dexec_next=container
  while [ "$dexec_n" -gt 0 ]; do
    dexec_arg="$1"
    shift
    set -- "$@" "$dexec_arg"
    case "$dexec_next:$dexec_arg" in
      value:*) dexec_next=container ;;
      container:-e | container:-u | container:-w) dexec_next=value ;;
      container:-*) ;;
      container:*)
        [ "$dexec_arg" != "$db_container" ] || set -- "$@" timeout "$dexec_limit"
        dexec_next=command
        ;;
    esac
    dexec_n=$((dexec_n - 1))
  done
  dexec_status=0
  perl -e 'my $limit = shift; my $pid = fork() // die "fork: $!"; if (!$pid) { exec(@ARGV) or die "exec: $!" }
    local $SIG{ALRM} = sub { kill "TERM", $pid; sleep 5; kill "KILL", $pid; exit 124 }; alarm $limit;
    waitpid($pid, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$((dexec_limit + 10))" docker exec "$@" || dexec_status=$?
  [ "$dexec_status" -ne 124 ] || exec_timed_out "docker exec $* (after ${dexec_limit}s)"
  return "$dexec_status"
}

dexec() {
  dexec_for "$exec_timeout" "$@"
}

check_server_major() {
  server_version="$(dexec "$db_container" psql -U postgres -Atc 'SHOW server_version_num')" \
    || { echo "could not read the PostgreSQL version of $db_container"; return 1; }
  [ "$((server_version / 10000))" = "$pg_major" ] \
    || { echo "$db_container runs PostgreSQL $((server_version / 10000)), but SP_PG_MAJOR selects $pg_major"; return 1; }
}

require_pg17() {
  [ "$pg_major" = 17 ] || { echo "$(basename "$0") runs on PostgreSQL 17 only, not SP_PG_MAJOR=$pg_major" >&2; exit 2; }
  mismatch="$(check_server_major)" || { echo "$mismatch" >&2; exit 1; }
}

checksum() {
  git -C "$root" hash-object --no-filters -- "$1"
}

snapshot_of() {
  for kind in image replay; do
    if [ -e "$snapshots/$1.$kind.sql.gz" ]; then
      echo "$snapshots/$1.$kind.sql.gz"
      return 0
    fi
  done
  echo "no snapshot for $1 in db/release_snapshots" >&2
  return 1
}

recreate_db() {
  dexec "$db_container" dropdb -U postgres --if-exists "$1"
  dexec "$db_container" createdb -U postgres "$1"
}

drop_transaction_timeout() {
  timeout_set='SET transaction_timeout = 0;'
  set_lines="$(grep -cxF "$timeout_set" "$tmpd/restore.sql")" || [ $? -eq 1 ] || exit 1
  preambles="$(grep -c '^-- Dumped by pg_dump version ' "$tmpd/restore.sql")" || [ $? -eq 1 ] || exit 1
  if [ "$set_lines" -lt 1 ] || [ "$set_lines" != "$preambles" ]; then
    echo "$(basename "$1"): expected one '$timeout_set' per pg_dump preamble, found $set_lines for $preambles pg_dump preambles" >&2
    exit 1
  fi
  grep -vxF "$timeout_set" "$tmpd/restore.sql" > "$tmpd/restore.filtered.sql" || exit 1
  mv "$tmpd/restore.filtered.sql" "$tmpd/restore.sql" || exit 1
  filtered_sum="$(checksum "$tmpd/restore.sql")" || exit 1
  echo "restoring $(basename "$1") into PostgreSQL $pg_major without its $set_lines '$timeout_set' lines: $filtered_sum" >&2
}

restore_snapshot() {
  gunzip -c "$1" > "$tmpd/restore.sql"
  [ "$pg_major" = 17 ] || drop_transaction_timeout "$1"
  dexec -i "$db_container" psql -U postgres -q -v ON_ERROR_STOP=1 -d "$2" < "$tmpd/restore.sql" >/dev/null
  restored="$(dexec "$db_container" psql -U postgres -d "$2" -Atc "SELECT to_regclass('public.schema_migrations') IS NOT NULL")"
  if [ "$restored" != "t" ]; then
    echo "restore of $(basename "$1") into $2 produced no schema_migrations table (corrupt or truncated snapshot?)" >&2
    exit 1
  fi
}

canon_dump() {
  dexec "$db_container" pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1" > "$tmpd/canon.sql"
  grep -vE '^\\(un)?restrict ' "$tmpd/canon.sql" | cat - "$root/scripts/schema_parity/lib.sh" "$root/scripts/schema_parity/normalize.sh" > "$tmpd/canon.key"
  memo="$work/canon/$(checksum "$tmpd/canon.key")"
  if [ ! -s "$memo" ]; then
    recreate_db "$1_rt"
    dexec -i "$db_container" psql -U postgres -q -v ON_ERROR_STOP=1 -d "$1_rt" < "$tmpd/canon.sql" >/dev/null
    dexec "$db_container" pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1_rt" > "$tmpd/canon.sql"
    dexec "$db_container" dropdb -U postgres "$1_rt"
    mkdir -p "$work/canon"
    "$root/scripts/schema_parity/normalize.sh" < "$tmpd/canon.sql" > "$memo.$$"
    mv "$memo.$$" "$memo"
  fi
  cat "$memo"
}

dump_snapshot() {
  tables="-t schema_migrations -t ar_internal_metadata"
  dexec "$db_container" psql -U postgres -d "$1" -Atc "SELECT to_regclass('public.data_migrations') IS NOT NULL" \
    | grep -qx t && tables="$tables -t data_migrations"
  dexec "$db_container" pg_dump -U postgres --schema-only --no-owner --no-privileges "$1" > "$2"
  dexec "$db_container" pg_dump -U postgres --data-only --no-owner --no-privileges $tables "$1" >> "$2"
}
