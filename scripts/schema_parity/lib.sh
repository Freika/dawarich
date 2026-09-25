work="$root/tmp/schema_parity"
snapshots="$root/db/release_snapshots"
rails_env="DATABASE_HOST=127.0.0.1 DATABASE_PORT=55532 DATABASE_USERNAME=postgres DATABASE_PASSWORD=parity REDIS_URL=redis://127.0.0.1:56479 SCHEMA=$work/throwaway_schema.rb RAILS_ENV=development"
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
  while [ "$dexec_n" -gt 0 ]; do
    dexec_arg="$1"
    shift
    set -- "$@" "$dexec_arg"
    [ "$dexec_arg" != sp-db ] || set -- "$@" timeout "$dexec_limit"
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
  dexec sp-db dropdb -U postgres --if-exists "$1"
  dexec sp-db createdb -U postgres "$1"
}

restore_snapshot() {
  gunzip -c "$1" > "$tmpd/restore.sql"
  dexec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$2" < "$tmpd/restore.sql" >/dev/null
  restored="$(dexec sp-db psql -U postgres -d "$2" -Atc "SELECT to_regclass('public.schema_migrations') IS NOT NULL")"
  if [ "$restored" != "t" ]; then
    echo "restore of $(basename "$1") into $2 produced no schema_migrations table (corrupt or truncated snapshot?)" >&2
    exit 1
  fi
}

canon_dump() {
  dexec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1" > "$tmpd/canon.sql"
  grep -vE '^\\(un)?restrict ' "$tmpd/canon.sql" | cat - "$root/scripts/schema_parity/lib.sh" "$root/scripts/schema_parity/normalize.sh" > "$tmpd/canon.key"
  memo="$work/canon/$(checksum "$tmpd/canon.key")"
  if [ ! -s "$memo" ]; then
    recreate_db "$1_rt"
    dexec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$1_rt" < "$tmpd/canon.sql" >/dev/null
    dexec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1_rt" > "$tmpd/canon.sql"
    dexec sp-db dropdb -U postgres "$1_rt"
    mkdir -p "$work/canon"
    "$root/scripts/schema_parity/normalize.sh" < "$tmpd/canon.sql" > "$memo.$$"
    mv "$memo.$$" "$memo"
  fi
  cat "$memo"
}

dump_snapshot() {
  tables="-t schema_migrations -t ar_internal_metadata"
  dexec sp-db psql -U postgres -d "$1" -Atc "SELECT to_regclass('public.data_migrations') IS NOT NULL" \
    | grep -qx t && tables="$tables -t data_migrations"
  dexec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges "$1" > "$2"
  dexec sp-db pg_dump -U postgres --data-only --no-owner --no-privileges $tables "$1" >> "$2"
}
