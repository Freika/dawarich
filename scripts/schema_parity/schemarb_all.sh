#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
mkdir -p "$work/diffs"
tmpd="$(mktemp -d "$work/.tmp.XXXXXX")"
cleanup() {
  rm -rf "$tmpd"
  for scratch in sp_schemarb sp_schemarb_state; do
    docker exec sp-db dropdb -U postgres --if-exists "$scratch" >/dev/null 2>&1 || true
    docker exec sp-db dropdb -U postgres --if-exists "${scratch}_rt" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ruby -rjson -e '
  blobs = Hash.new { |hash, blob| hash[blob] = {} }
  JSON.parse(File.read(ARGV[0])).fetch("states").each do |state|
    state.fetch("releases").each do |tag|
      blob = IO.popen(["git", "-C", ARGV[1], "rev-parse", "-q", "--verify", "refs/tags/#{tag}:db/schema.rb"], &:read).strip
      (blobs[blob][state.fetch("first_release")] ||= []) << tag unless blob.empty?
    end
  end
  abort "no release tag ships db/schema.rb" if blobs.empty?
  blobs.each do |blob, states|
    first = states.values.first.first
    states.each { |state, tags| puts [blob, state, tags.join(","), first].join(" ") }
  end' "$root/db/release_migrations.json" "$root" > "$tmpd/pairs"

ledger_sql() {
  (cd "$root" && ruby -I lib -r schema_parity/release_map -r schema_parity/git_tags -e '
    tag, schema_file = ARGV
    version = File.read(schema_file)[/define\(version: ([\d_]+)\)/, 1]&.delete("_") or abort "no define(version:) in the schema.rb of #{tag}"
    paths = SchemaParity::GitTags.files_at(tag)
    schema = ([version] + SchemaParity::ReleaseMap.versions(paths, "db/migrate").select { _1.to_i < version.to_i }).uniq.sort
    data = SchemaParity::ReleaseMap.versions(paths, "db/data")
    values = ->(versions) { versions.map { |v| "(\x27#{v}\x27)" }.join(",") }
    puts "TRUNCATE schema_migrations;", "INSERT INTO schema_migrations (version) VALUES #{values[schema]};"
    unless data.empty?
      puts "CREATE TABLE IF NOT EXISTS data_migrations (version varchar PRIMARY KEY);"
      puts "INSERT INTO data_migrations (version) VALUES #{values[data]} ON CONFLICT DO NOTHING;"
    end' "$1" "$2")
}

load_blob() {
  git -C "$root" cat-file blob "$1" > "$tmpd/schema.rb"
  recreate_db sp_schemarb
  if (cd "$root" && env $rails_env SKIP_TEST_DATABASE=true SCHEMA="$tmpd/schema.rb" DATABASE_NAME=sp_schemarb \
    bin/rails db:schema:load) > "$tmpd/load.log" 2>&1; then
    ledger_sql "$2" "$tmpd/schema.rb" > "$tmpd/ledger.sql"
    docker exec -i sp-db psql -U postgres -q -v ON_ERROR_STOP=1 -d sp_schemarb < "$tmpd/ledger.sql" >/dev/null
    canon_dump sp_schemarb > "$tmpd/blob.sql"
    load_result=ok
  else
    load_result="$(awk '/aborted!$/ { getline; print; exit }' "$tmpd/load.log")"
    [ -n "$load_result" ] || load_result="$(tail -n 1 "$tmpd/load.log")"
  fi
}

canon_state() {
  snapshot="$(snapshot_of "$1")"
  recreate_db sp_schemarb_state
  restore_snapshot "$snapshot" sp_schemarb_state
  canon_dump sp_schemarb_state > "$tmpd/state.$1.sql"
  docker exec sp-db dropdb -U postgres sp_schemarb_state
}

mkdir -p "$tmpd/out"
rm -f "$work"/diffs/*.schemarb.diff
printf 'blob\tstate\treleases\tresult\tdiff_lines\tsnapshot\tnote\n' > "$tmpd/schemarb.tsv"
loaded=""
while read -r blob state releases first <&3; do
  if [ "$blob" != "$loaded" ]; then
    load_blob "$blob" "$first"
    loaded="$blob"
  fi
  result=unloadable
  lines=-
  stored=-
  note=-
  if [ "$load_result" != ok ]; then
    note="$load_result"
  else
    [ -s "$tmpd/state.$state.sql" ] || canon_state "$state"
    diff -u "$tmpd/state.$state.sql" "$tmpd/blob.sql" > "$tmpd/diff" || [ $? -eq 1 ]
    lines="$(wc -l < "$tmpd/diff" | tr -d ' ')"
    result=identical
    if [ "$lines" -gt 0 ]; then
      result=differs
      stored="$first.schemarb.sql.gz"
      cp "$tmpd/diff" "$work/diffs/${releases%%,*}.schemarb.diff"
      if [ ! -e "$tmpd/out/$stored" ]; then
        dump_snapshot sp_schemarb "$tmpd/store.sql"
        gzip -9 -n -c "$tmpd/store.sql" > "$tmpd/out/$stored"
      fi
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$blob" "$state" "$releases" "$result" "$lines" "$stored" "$note" >> "$tmpd/schemarb.tsv"
  echo "$blob $state ${releases%%,*} $result $lines" >&2
done 3< "$tmpd/pairs"

rm -f "$snapshots"/*.schemarb.sql.gz
for file in "$tmpd"/out/*.schemarb.sql.gz; do
  [ ! -e "$file" ] || mv "$file" "$snapshots/"
done
mv "$tmpd/schemarb.tsv" "$snapshots/schemarb.tsv"
awk -F '\t' 'NR > 1 && !($1 in seen) { seen[$1] = 1; blobs++ } NR > 1 { count[$4]++ } END {
  printf "%d blobs, %d blob/state pairs: %d identical, %d differ, %d unloadable\n",
    blobs, NR - 1, count["identical"], count["differs"], count["unloadable"] }' "$snapshots/schemarb.tsv"
