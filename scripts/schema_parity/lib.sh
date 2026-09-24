work="$root/tmp/schema_parity"
snapshots="$root/db/release_snapshots"
rails_env="DATABASE_HOST=127.0.0.1 DATABASE_PORT=55532 DATABASE_USERNAME=postgres DATABASE_PASSWORD=parity REDIS_URL=redis://127.0.0.1:56479 SCHEMA=$work/throwaway_schema.rb RAILS_ENV=development"

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
  docker exec sp-db dropdb -U postgres --if-exists "$1"
  docker exec sp-db createdb -U postgres "$1"
}

restore_snapshot() {
  gunzip -c "$1" > "$tmpd/restore.sql"
  docker exec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$2" < "$tmpd/restore.sql" >/dev/null
  restored="$(docker exec sp-db psql -U postgres -d "$2" -Atc "SELECT to_regclass('public.schema_migrations') IS NOT NULL")"
  if [ "$restored" != "t" ]; then
    echo "restore of $(basename "$1") into $2 produced no schema_migrations table (corrupt or truncated snapshot?)" >&2
    exit 1
  fi
}

canon_dump() {
  recreate_db "$1_rt"
  docker exec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1" > "$tmpd/canon.sql"
  docker exec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$1_rt" < "$tmpd/canon.sql" >/dev/null
  docker exec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges --exclude-schema=phoenix --exclude-schema=oban "$1_rt" > "$tmpd/canon.sql"
  docker exec sp-db dropdb -U postgres "$1_rt"
  "$root/scripts/schema_parity/normalize.sh" < "$tmpd/canon.sql"
}

dump_snapshot() {
  tables="-t schema_migrations -t ar_internal_metadata"
  docker exec sp-db psql -U postgres -d "$1" -Atc "SELECT to_regclass('public.data_migrations') IS NOT NULL" \
    | grep -qx t && tables="$tables -t data_migrations"
  docker exec sp-db pg_dump -U postgres --schema-only --no-owner --no-privileges "$1" > "$2"
  docker exec sp-db pg_dump -U postgres --data-only --no-owner --no-privileges $tables "$1" >> "$2"
}
