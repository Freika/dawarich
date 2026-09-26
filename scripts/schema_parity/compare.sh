#!/bin/sh
set -eu
release="$1"
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
require_pg17
mkdir -p "$work/diffs"
tmpd="$(mktemp -d "$work/.tmp.XXXXXX")"
cleanup() {
  rm -rf "$tmpd"
  for scratch in sp_fresh sp_upgrade sp_replay sp_image; do
    docker exec "$db_container" dropdb -U postgres --if-exists "$scratch" >/dev/null 2>&1 || true
    docker exec "$db_container" dropdb -U postgres --if-exists "${scratch}_rt" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

key="$({ ls "$root/db/migrate"; cat "$root"/db/migrate/*.rb; } | cksum | tr ' ' -)"
fresh="$work/fresh.$key.sql"
if [ ! -s "$fresh" ]; then
  rm -f "$work"/fresh*.sql "$work/throwaway_schema.rb"
  recreate_db sp_fresh
  (cd "$root" && env $rails_env DATABASE_NAME=sp_fresh bin/rails db:migrate >/dev/null)
  canon_dump sp_fresh > "$tmpd/fresh.sql"
  mv "$tmpd/fresh.sql" "$fresh"
fi

snapshot="${2:-}"
label="$release"
if [ -n "$snapshot" ]; then
  label="$(basename "$snapshot" .sql.gz)"
else
  snapshot="$(snapshot_of "$release")"
fi
rm -f "$work/diffs/$label.upgrade.diff" "$work/diffs/$label.replay.diff"
replay_result=n/a
recreate_db sp_upgrade
restore_snapshot "$snapshot" sp_upgrade
(cd "$root" && env $rails_env DATABASE_NAME=sp_upgrade bin/rails db:migrate >/dev/null)
canon_dump sp_upgrade > "$tmpd/upgrade.sql"
diff -u "$fresh" "$tmpd/upgrade.sql" > "$work/diffs/$label.upgrade.diff" || [ $? -eq 1 ]

case "$snapshot" in
  *.image.sql.gz)
    missing="$(ruby -rjson -e '
      states = JSON.parse(File.read(File.join(ARGV[1], "db/release_migrations.json")))["states"]
      upto = states.index { _1["first_release"] == ARGV[0] } or abort "no state #{ARGV[0]} in db/release_migrations.json"
      wanted = states[0..upto].reduce([]) { |versions, state| versions + state["schema_added"] - state["schema_removed"] }
      present = Dir[File.join(ARGV[1], "db/migrate/*.rb")].filter_map { File.basename(_1)[/\A(\d+)_/, 1] }
      puts (wanted - present).join(",")' "$release" "$root")"
    if [ -n "$missing" ]; then
      replay_result="not-reproducible missing:$missing"
    else
      recreate_db sp_replay
      (cd "$root" && env $rails_env DATABASE_NAME=sp_replay bin/rails runner scripts/schema_parity/replay.rb "$release" >/dev/null)
      canon_dump sp_replay > "$tmpd/replay.sql"
      recreate_db sp_image
      restore_snapshot "$snapshot" sp_image
      canon_dump sp_image > "$tmpd/image.sql"
      diff -u "$tmpd/image.sql" "$tmpd/replay.sql" > "$work/diffs/$release.replay.diff" || [ $? -eq 1 ]
      replay_result="$(wc -l < "$work/diffs/$release.replay.diff" | tr -d ' ')"
    fi
    ;;
esac

echo "$label upgrade:$(wc -l < "$work/diffs/$label.upgrade.diff" | tr -d ' ') replay:$replay_result"
