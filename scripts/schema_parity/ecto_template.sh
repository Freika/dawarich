template_name() {
  {
    echo "template upto=$2 extra=$3 shift=$shift_to boot=$4"
    case "$1" in
      none | empty) echo "$1" ;;
      *) git -C "$root" hash-object --no-filters -- "$1" || return 1 ;;
    esac
    for file in "$fixture" "$envfile"; do
      if [ -f "$file" ]; then git -C "$root" hash-object --no-filters -- "$file" || return 1; else echo -; fi
    done
    echo "$code_key"
  } > "$tmpd/template.input" || return 1
  sum="$(git -C "$root" hash-object --no-filters -- "$tmpd/template.input")" || return 1
  echo "sp_t_$sum"
}

build_template() {
  build_db="sp_b_$run_id"
  built_from="$(date -u +%s)"
  recreate_db "$build_db"
  dexec sp-db psql -U postgres -qc "ALTER DATABASE $build_db SET timezone TO 'Pacific/Chatham'" >/dev/null
  case "$2" in
    none) ;;
    empty) rails_in "$build_db" runner 'ActiveRecord::Base.connection_pool.schema_migration.create_table; ActiveRecord::Base.connection_pool.internal_metadata.create_table' >/dev/null ;;
    *) restore_snapshot "$2" "$build_db" ;;
  esac
  [ -z "$3" ] || rails_in "$build_db" runner "ActiveRecord::Base.connection_pool.migration_context.migrate($3)" >/dev/null
  [ -z "$4" ] || query "$build_db" "INSERT INTO schema_migrations (version) VALUES ('$4')" >/dev/null
  [ "$shift_to" = 0 ] || query "$build_db" "SELECT setval(c.oid::regclass, $shift_to) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname = 'public'" >/dev/null
  [ ! -s "$fixture" ] || dexec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d "$build_db" < "$fixture" >/dev/null
  [ "$5" = no ] || rails_in "$build_db" runner 'nil' >/dev/null
  built_to="$(date -u +%s)"
  sleep 1
  dexec sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -c "COMMENT ON DATABASE $build_db IS '$built_from $built_to'" \
    -c "ALTER DATABASE $build_db WITH IS_TEMPLATE true ALLOW_CONNECTIONS false" >/dev/null
  if dexec sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -c "ALTER DATABASE $build_db RENAME TO $1" >/dev/null 2>&1; then
    build_db=""
  fi
}

prepare() {
  template_boot=yes
  [ "$kind" != refused ] || template_boot=no
  template="$(template_name "$2" "$3" "$4" "$template_boot")" || fail "could not hash the template inputs of $check"
  [ "$(query postgres "SELECT count(*) FROM pg_database WHERE datname = '$template'")" = 1 ] \
    || build_template "$template" "$2" "$3" "$4" "$template_boot"
  template_window="$(dexec sp-db psql -U postgres -qAt -v ON_ERROR_STOP=1 -c "CREATE DATABASE $1 TEMPLATE $template" \
    -c "ALTER DATABASE $1 SET timezone TO 'Pacific/Chatham'" \
    -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$template'")" \
    || fail "could not clone $template into $1"
  echo "$template_window" | grep -Eqx '[0-9]+ [0-9]+' || fail "template $template has no build window ($template_window)"
  echo "$template" >> "$work/ecto/templates.used"
}

prune_databases() {
  dexec sp-db psql -U postgres -qAt -c "SELECT datname FROM pg_database WHERE datname ~ '^sp_[tbre]_'" > "$work/ecto/.databases" || return 1
  LC_ALL=C sort -u "$work/ecto/templates.used" > "$work/ecto/.templates.used" || return 1
  while IFS= read -r db; do
    case "$db" in
      sp_t_*) grep -qxF "$db" "$work/ecto/.templates.used" || echo "$db" ;;
      *)
        owner="$(echo "$db" | sed -n 's/^sp_[bre]_\([0-9][0-9]*\)x.*/\1/p')"
        [ -z "$owner" ] || kill -0 "$owner" 2>/dev/null || echo "$db"
        ;;
    esac
  done < "$work/ecto/.databases" > "$work/ecto/.databases.stale"
  [ -s "$work/ecto/.databases.stale" ] || return 0
  drop_sql $(cat "$work/ecto/.databases.stale") | dexec -i sp-db psql -U postgres -q >/dev/null
}
