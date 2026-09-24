ecto_env="MIX_ENV=test DATABASE_HOST=127.0.0.1 DATABASE_PORT=55532 DATABASE_USERNAME=postgres DATABASE_PASSWORD=parity"
expectations="$root/scripts/schema_parity/ecto_expectations.tsv"
holder_seconds=150
holder_pid=""
watch_pid=""

fail() {
  echo "$check FAIL $*"
  exit 1
}

scrubbed() {
  env -i PATH="$PATH" HOME="$HOME" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$@"
}

query() {
  docker exec -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAtc "$2"
}

code_key() {
  (
    cd "$root"
    LC_ALL=C ls db/migrate
    cat db/migrate/*.rb db/release_migrations.json Gemfile.lock
    find app config lib -type f -print0 | LC_ALL=C sort -z | xargs -0 cat
    for file in .env*; do [ ! -f "$file" ] || cat "$file"; done
    cat scripts/schema_parity/*.sh scripts/schema_parity/*.rb scripts/schema_parity/*.tsv
    ruby -v
  ) | cksum | tr ' ' -
}

key_of() {
  { echo "$check"; for file in "$@"; do [ -z "$file" ] || [ ! -f "$file" ] || cat "$file"; done; } | cksum | tr ' ' -
}

rows_sql="WITH objects AS (
  SELECT c.relname, c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'S') AND NOT c.relispartition
    AND c.relname NOT IN ('schema_migrations', 'ar_internal_metadata', 'data_migrations')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
)
SELECT CASE relkind
  WHEN 'S' THEN format('COPY (SELECT %L, last_value, is_called FROM public.%I) TO STDOUT;', 'sequence ' || relname, relname)
  ELSE format('COPY (SELECT %L, t.* FROM public.%I t) TO STDOUT;', relname, relname)
END FROM objects
UNION ALL
SELECT format('SELECT %L || (%s);', '#rows ', coalesce(string_agg(CASE relkind WHEN 'S' THEN '1'
  ELSE format('(SELECT count(*) FROM public.%I)', relname) END, ' + '), '0')) FROM objects"

record() {
  canon_dump "$1" > "$2.schema"
  if [ "$(query "$1" "SELECT to_regclass('public.schema_migrations') IS NOT NULL")" = t ]; then
    query "$1" 'SELECT version FROM public.schema_migrations ORDER BY version' > "$2.ledger"
  else
    : > "$2.ledger"
  fi
  query "$1" "SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position" > "$2.columns"
  query "$1" "$rows_sql" > "$tmpd/rows.copy"
  docker exec -i -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAt < "$tmpd/rows.copy" > "$tmpd/rows.raw" \
    || fail "could not copy the rows of $1"
  expected="$(sed -n 's/^#rows //p' "$tmpd/rows.raw")"
  grep -v '^#rows ' "$tmpd/rows.raw" > "$tmpd/rows.data" || [ $? -eq 1 ]
  ruby "$root/scripts/schema_parity/canon.rb" rows "$started" "$(date -u +%s)" < "$tmpd/rows.data" > "$tmpd/rows.canon" \
    || fail "canon.rb rows failed on $1"
  LC_ALL=C sort "$tmpd/rows.canon" > "$2.rows"
  recorded="$(wc -l < "$2.rows" | tr -d ' ')"
  [ -n "$expected" ] && [ "$recorded" = "$expected" ] || fail "recorded $recorded of ${expected:-?} rows of $1"
}

canon_jobs() {
  ruby "$root/scripts/schema_parity/canon.rb" jobs < "$1" > "$2" || fail "canon.rb jobs failed on $1"
}

failure_class() {
  ruby "$root/scripts/schema_parity/canon.rb" failure < "$1" || fail "canon.rb failure failed on $1"
}

diff_parts() {
  left="$1"
  right="$2"
  shift 2
  failures=""
  for part in "$@"; do
    if diff -u "$left.$part" "$right.$part" > "$out/diffs/$name.$part.diff" 2>&1; then
      rm -f "$out/diffs/$name.$part.diff"
    else
      failures="$failures $part:$(wc -l < "$out/diffs/$name.$part.diff" | tr -d ' ')"
    fi
  done
}

hold() {
  [ -n "$holder_table" ] || return 0
  docker exec sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qc \
    "BEGIN; LOCK TABLE $holder_table IN ROW EXCLUSIVE MODE; SELECT pg_sleep($holder_seconds); COMMIT;" \
    > /dev/null 2> "$tmpd/holder.err" &
  holder_pid=$!
  waited=0
  until [ "$(query "$1" "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid = l.relation WHERE c.relname = '$holder_table' AND l.mode = 'RowExclusiveLock' AND l.granted AND l.pid <> pg_backend_pid() AND l.database = (SELECT oid FROM pg_database WHERE datname = '$1')")" -ge 1 ]; do
    if ! kill -0 "$holder_pid" 2>/dev/null || [ "$waited" -ge 60 ]; then
      fail "holder never took its lock on $holder_table ($(tr '\n' ' ' < "$tmpd/holder.err"))"
    fi
    waited=$((waited + 1))
    sleep 1
  done
  rm -f "$tmpd/watch.stop"
  (
    while [ ! -e "$tmpd/watch.stop" ]; do
      echo "SELECT l.pid || ' ' || a.xact_start FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid WHERE l.locktype = 'relation' AND NOT l.granted AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database()) AND l.relation = '$holder_table'::regclass;"
      sleep 0.2
    done
  ) | docker exec -i -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAt > "$tmpd/watch.log" 2> "$tmpd/watch.err" &
  watch_pid=$!
}

unhold() {
  [ -n "$holder_pid" ] || return 0
  touch "$tmpd/watch.stop"
  wait "$watch_pid" || fail "the lock watcher on $holder_table failed ($(tr '\n' ' ' < "$tmpd/watch.err"))"
  watch_pid=""
  grep -v '^$' "$tmpd/watch.log" | LC_ALL=C sort -u | wc -l | tr -d ' ' > "$2.waits"
  query "$1" "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$1' AND query LIKE '%pg_sleep($holder_seconds)%' AND pid <> pg_backend_pid()" >/dev/null
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=""
}

release_harness() {
  [ -z "$watch_pid" ] || { touch "$tmpd/watch.stop"; kill "$watch_pid" >/dev/null 2>&1 || true; }
  [ -z "$holder_pid" ] || kill "$holder_pid" >/dev/null 2>&1 || true
  rm -rf "$tmpd"
  for scratch in "$@"; do
    docker exec sp-db dropdb -U postgres --if-exists --force "$scratch" >/dev/null 2>&1 || true
    docker exec sp-db dropdb -U postgres --if-exists "${scratch}_rt" >/dev/null 2>&1 || true
  done
}
