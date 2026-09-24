#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
mkdir -p "$work/ecto"
usage="usage: ecto_prove.sh [--shard K/N] --list | all | <check>..."
shard=""
if [ "${1:-}" = --shard ]; then
  shard="${2:-}"
  k="${shard%%/*}"
  n="${shard#*/}"
  case "$k/$n" in
    */*/* | /* | */ | *[!0-9/]*) echo "--shard needs K/N with integers 1 <= K <= N, got '$shard'" >&2; exit 2 ;;
  esac
  if [ "$shard" = "$k" ] || [ "$k" -lt 1 ] || [ "$k" -gt "$n" ]; then
    echo "--shard needs K/N with integers 1 <= K <= N, got '$shard'" >&2
    exit 2
  fi
  shift 2
fi

list_checks() {
  ruby -rjson -e '
    root = ARGV[0]
    states = JSON.parse(File.read(File.join(root, "db/release_migrations.json"))).fetch("states")
    floor = states.index { _1.fetch("first_release") == "0.37.2" } or abort "no 0.37.2 state in db/release_migrations.json"
    present = Dir[File.join(root, "db/migrate/*.rb")].filter_map { File.basename(_1)[/\A(\d+)_/, 1] }
    listed = states.flat_map { _1.fetch("schema_added") }
    fixtures = Dir[File.join(root, "scripts/schema_parity/fixtures/*.sql")].sort.map { File.basename(_1, ".sql") }
    declared = File.readlines(File.join(root, "scripts/schema_parity/ecto_expectations.tsv"), chomp: true).map { _1.split("\t").first }
    puts "fresh", "fresh:empty"
    states[(floor + 1)..].each { |state| puts "step:#{state.fetch("first_release")}" if (state.fetch("schema_added") & present).any? }
    puts "step:unreleased" if (present - listed).any?
    fixtures.each do |fixture|
      puts "rows:#{fixture}"
      puts "rows:#{fixture}~shifted" unless fixture.include?("--unported-")
    end
    declared.grep(/\Acontended:/).each { puts _1 }
    states[floor..].each { |state| puts "upgrade:#{state.fetch("first_release")}" }
    Dir[File.join(root, "db/release_snapshots/*.schemarb.sql.gz")].sort.each do |file|
      release = File.basename(file, ".schemarb.sql.gz")
      puts "upgrade:#{release}.schemarb" if Gem::Version.new(release) >= Gem::Version.new("0.37.2")
    end
    puts "upgrade:0.37.2+20241030152025", "upgrade:0.37.2@20260108192905", "upgrade:1.3.1@20260301201446"
    declared.grep(/\Arefused:/).each { puts _1 }' "$root"
}

select_shard() {
  if [ -z "$shard" ]; then cat; else awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1'; fi
}

selected() {
  checks="$(list_checks)" || { echo "listing the checks failed" >&2; exit 2; }
  picked="$(printf '%s\n' "$checks" | select_shard)"
  [ -n "$picked" ] || { echo "no checks selected${shard:+ for shard $shard}" >&2; exit 2; }
  printf '%s\n' "$picked"
}

summary="$work/ecto/summary.txt"
[ -z "$shard" ] || summary="$work/ecto/summary.$k-$n.txt"

case "${1:-}" in
  --list) selected; exit 0 ;;
  all)
    picked="$(selected)" || exit 2
    set -- $picked
    ;;
  "") echo "$usage" >&2; exit 2 ;;
esac

if ! (cd "$root/app-phoenix" && scrubbed $ecto_env mix compile) >> "$work/ecto/prove.log" 2>&1; then
  echo "mix compile failed in app-phoenix (see tmp/schema_parity/ecto/prove.log)" >&2
  exit 2
fi
[ "${picked+set}" != set ] || : > "$summary"

failed=0
for check in "$@"; do
  echo "== start $(date -u +%s) $check" >> "$work/ecto/prove.log"
  if line="$("$root/scripts/schema_parity/ecto_check.sh" "$check" 2>> "$work/ecto/prove.log")"; then
    status=0
  else
    status=1
    [ -n "$line" ] || line="$check FAIL error (see tmp/schema_parity/ecto/prove.log)"
    failed=$((failed + 1))
  fi
  echo "== end $(date -u +%s) $check $status" >> "$work/ecto/prove.log"
  echo "$line" | tee -a "$summary"
done
echo "ran $# checks, $failed failed"
[ "$failed" -eq 0 ]
