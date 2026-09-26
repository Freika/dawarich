ecto_env="MIX_ENV=test DATABASE_HOST=127.0.0.1 DATABASE_PORT=55532 DATABASE_USERNAME=postgres DATABASE_PASSWORD=parity"
expectations="$root/scripts/schema_parity/ecto_expectations.tsv"
encrypted_columns="$root/scripts/schema_parity/encrypted_columns.tsv"
holder_seconds=150
parts="schema ledger columns invalid rows jobs"
holder_pid=""
watch_pid=""
build_db=""
releasing=""
template_window=""

fail() {
  echo "$check FAIL $*"
  exit 1
}

scrubbed() {
  env -i PATH="$PATH" HOME="$HOME" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$@"
}

query() {
  dexec -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAtc "$2"
}

code_key() {
  (
    cd "$root" || exit 1
    set -- db/migrate db/release_migrations.json app ':(exclude)app/assets' config lib Gemfile.lock .ruby-version \
      .tool-versions scripts/schema_parity/*.sh scripts/schema_parity/*.rb scripts/schema_parity/encrypted_columns.tsv
    git -c core.quotepath=off ls-files -c -o --exclude-standard -- "$@" > "$tmpd/key.files" || exit 1
    git -c core.quotepath=off ls-files -d -- "$@" > "$tmpd/key.deleted" || exit 1
    grep -vxF -f "$tmpd/key.deleted" "$tmpd/key.files" > "$tmpd/key.present" || [ $? -eq 1 ] || exit 1
    git hash-object --no-filters --stdin-paths < "$tmpd/key.present" > "$tmpd/key.blobs" || exit 1
    paste "$tmpd/key.present" "$tmpd/key.blobs" || exit 1
    sed 's/$/ deleted/' "$tmpd/key.deleted" || exit 1
    for file in .env*; do [ ! -f "$file" ] || cat "$file" || exit 1; done
    scrubbed ruby -v || exit 1
  ) > "$tmpd/key.input" && checksum "$tmpd/key.input"
}

key_of() {
  {
    echo "$check"
    for file in "$@"; do [ -z "$file" ] || [ ! -f "$file" ] || cat "$file" || return 1; done
  } > "$tmpd/key_of.input" && checksum "$tmpd/key_of.input"
}

local_dotenv() {
  for file in .env.development.local .env.local .env; do
    [ ! -e "$root/$file" ] || { echo "$root/$file"; return 0; }
  done
  return 1
}

list_checks() {
  ruby -rjson "$root/scripts/schema_parity/list_checks.rb" "$root"
}

invalid_sql="SELECT i.indrelid::regclass::text, i.indexrelid::regclass::text, pg_get_indexdef(i.indexrelid)
FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT i.indisvalid AND n.nspname NOT IN ('phoenix', 'oban')
ORDER BY i.indrelid::regclass::text COLLATE \"C\", i.indexrelid::regclass::text COLLATE \"C\""

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

encrypted_sql() {
  enc_values=""
  while IFS="$(printf '\t')" read -r enc_table enc_column; do
    enc_values="$enc_values${enc_values:+, }('$enc_table', '$enc_column')"
  done < "$encrypted_columns"
  [ -n "$enc_values" ] || return 1
  echo "SELECT format('SELECT 1 FROM public.%I WHERE %I IS NOT NULL LIMIT 1;', table_name, column_name)
FROM information_schema.columns
WHERE table_schema = 'public' AND (table_name::text, column_name::text) IN (VALUES $enc_values)"
}

decrypted_columns() {
  : > "$tmpd/decrypt.sql"
  enc_checks="$(encrypted_sql)" || fail "could not read the encrypted columns in $encrypted_columns"
  query "$1" "$enc_checks" > "$tmpd/encrypted.sql" || fail "could not look for encrypted columns in $1"
  dexec -i -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAt < "$tmpd/encrypted.sql" \
    > "$tmpd/encrypted.found" || fail "could not look for encrypted values in $1"
  [ -s "$tmpd/encrypted.found" ] || return 0
  (cd "$root" && scrubbed $rails_env $fixture_env PGOPTIONS='-c default_transaction_read_only=on' DATABASE_NAME="$1" \
    bin/rails runner scripts/schema_parity/decrypt_columns.rb "$2" "$encrypted_columns" "$tmpd/decrypt.sql") \
    > "$tmpd/decrypt.out" 2>&1 \
    || fail "$(grep -m 1 '^decrypt_columns.rb: ' "$tmpd/decrypt.out" || tail -n 1 "$tmpd/decrypt.out")"
}

record() {
  canon_dump "$1" > "$2.schema"
  has_ledger="$(query "$1" "SELECT to_regclass('public.schema_migrations') IS NOT NULL")" || fail "could not look for the ledger of $1"
  if [ "$has_ledger" = t ]; then
    query "$1" 'SELECT version FROM public.schema_migrations ORDER BY version' > "$2.ledger"
  else
    : > "$2.ledger"
  fi
  query "$1" "SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position" > "$2.columns"
  query "$1" "$invalid_sql" > "$2.invalid"
  query "$1" "$rows_sql" > "$tmpd/rows.copy"
  decrypted_columns "$1" "$(basename "$2")"
  { echo 'BEGIN;'; cat "$tmpd/decrypt.sql" "$tmpd/rows.copy"; echo 'ROLLBACK;'; } > "$tmpd/rows.sql"
  dexec -i -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAt < "$tmpd/rows.sql" > "$tmpd/rows.raw" \
    || fail "could not copy the rows of $1"
  expected="$(sed -n 's/^#rows //p' "$tmpd/rows.raw")"
  grep -v '^#rows ' "$tmpd/rows.raw" > "$tmpd/rows.data" || [ $? -eq 1 ]
  ruby "$root/scripts/schema_parity/canon.rb" rows "$started" "$(date -u +%s)" $template_window < "$tmpd/rows.data" > "$tmpd/rows.canon" \
    || fail "canon.rb rows failed on $1"
  LC_ALL=C sort "$tmpd/rows.canon" > "$2.rows"
  recorded="$(wc -l < "$2.rows" | tr -d ' ')"
  [ -n "$expected" ] && [ "$recorded" = "$expected" ] || fail "recorded $recorded of ${expected:-?} rows of $1"
}

canon_jobs() {
  ruby "$root/scripts/schema_parity/canon.rb" jobs < "$1" > "$2" || fail "canon.rb jobs failed on $1"
}

canon_message() {
  ruby "$root/scripts/schema_parity/canon.rb" message "$started" "$(date -u +%s)" $template_window < "$1" > "$2" || fail "canon.rb message failed on $1"
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
  dexec_for "$((holder_seconds + exec_timeout))" sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qc \
    "BEGIN; LOCK TABLE $holder_table IN ROW EXCLUSIVE MODE; SELECT pg_sleep($holder_seconds); COMMIT;" \
    > /dev/null 2> "$tmpd/holder.err" 3>&- &
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
  ) 3>&- | dexec_for "$((holder_seconds + exec_timeout))" -i -e PGTZ=UTC sp-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -qAt > "$tmpd/watch.log" 2> "$tmpd/watch.err" 3>&- &
  watch_pid=$!
}

unhold() {
  [ -n "$holder_pid" ] || return 0
  touch "$tmpd/watch.stop"
  wait "$watch_pid" || fail "the lock watcher on $holder_table failed ($(tr '\n' ' ' < "$tmpd/watch.err"))"
  watch_pid=""
  grep -v '^$' "$tmpd/watch.log" > "$tmpd/watch.lines" || [ $? -eq 1 ] || fail "could not read the lock watcher's log"
  LC_ALL=C sort -u "$tmpd/watch.lines" > "$tmpd/watch.uniq" || fail "could not count the lock waits"
  waits="$(wc -l < "$tmpd/watch.uniq")" || fail "could not count the lock waits"
  echo $waits > "$2.waits"
  query "$1" "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$1' AND query LIKE '%pg_sleep($holder_seconds)%' AND pid <> pg_backend_pid()" >/dev/null
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=""
}

drop_sql() {
  for db in "$@"; do
    printf 'ALTER DATABASE %s IS_TEMPLATE false;\nDROP DATABASE IF EXISTS %s WITH (FORCE);\n' "$db" "$db"
  done
}

release_harness() {
  releasing=1
  [ ! -s "$tmpd/timed_out" ] || echo "$check FAIL timed out: $(cat "$tmpd/timed_out")" >&3
  [ -z "$watch_pid" ] || { touch "$tmpd/watch.stop"; kill "$watch_pid" >/dev/null 2>&1 || true; }
  [ -z "$holder_pid" ] || kill "$holder_pid" >/dev/null 2>&1 || true
  drop_sql "$@" $build_db $(printf '%s_rt ' "$@") | dexec -i sp-db psql -U postgres -q >/dev/null 2>&1 || true
  rm -rf "$tmpd"
}
