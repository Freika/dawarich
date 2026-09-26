#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
. "$root/scripts/schema_parity/ecto_template.sh"
mkdir -p "$work/ecto"
usage="usage: ecto_prove.sh [--shard K/N] [--jobs N] --list | all | <check>..."
shard=""
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || cores=1
jobs=$((cores / 2))
[ "$jobs" -ge 1 ] || jobs=1
while :; do
  case "${1:-}" in
    --shard)
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
      ;;
    --jobs)
      case "${2:-}" in
        "" | *[!0-9]* | 0*) echo "--jobs needs an integer N >= 1, got '${2:-}'" >&2; exit 2 ;;
      esac
      jobs="$2"
      shift 2
      ;;
    *) break ;;
  esac
done

summary="$work/ecto/summary.txt"
[ -z "$shard" ] || summary="$work/ecto/summary.$k-$n.txt"

abort_run() {
  echo "ABORTED $*" > "$summary"
  echo "$*" >&2
  exit 2
}

terminated() {
  trap '' TERM
  unfinished="$(awk '$1 == "==" && $2 == "start" { s[$4] = 1 } $1 == "==" && $2 == "end" { delete s[$4] }
    END { for (c in s) print c }' "$lanes"/log.* 2>/dev/null | LC_ALL=C sort | paste -s -d ' ' -)"
  echo "ABORTED terminated $phase${unfinished:+ (unfinished: $unfinished)}" >> "$summary"
  echo "terminated $phase" >&2
  exit 2
}

duplicates_in() {
  printf '%s\n' "$@" | LC_ALL=C sort | uniq -d | paste -s -d ' ' -
}

select_shard() {
  if [ -z "$shard" ]; then cat; else awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1'; fi
}

case "${1:-}" in
  --list)
    checks="$(list_checks)" || exit 2
    picked="$(printf '%s\n' "$checks" | select_shard)"
    [ -n "$picked" ] || { echo "no checks selected${shard:+ for shard $shard}" >&2; exit 2; }
    duplicates="$(duplicates_in $picked)"
    [ -z "$duplicates" ] || { echo "duplicate checks: $duplicates" >&2; exit 2; }
    printf '%s\n' "$picked"
    exit 0
    ;;
  all)
    checks="$(list_checks 2> "$work/ecto/.list.err")" || abort_run "listing the checks failed: $(tr '\n' ' ' < "$work/ecto/.list.err")"
    picked="$(printf '%s\n' "$checks" | select_shard)"
    [ -n "$picked" ] || abort_run "no checks selected${shard:+ for shard $shard}"
    set -- $picked
    ;;
  "") echo "$usage" >&2; exit 2 ;;
esac
trap 'abort_run "terminated before the checks started"' TERM
duplicates="$(duplicates_in "$@")"
[ -z "$duplicates" ] || abort_run "duplicate checks: $duplicates"

if dotenv="$(local_dotenv)"; then
  abort_run "refusing to run: $dotenv exists and dotenv would load it into the Rails side only"
fi
trap 'abort_run "timed out reading the PostgreSQL version of $db_container"' TERM
mismatch="$(check_server_major)" || abort_run "$mismatch"
trap 'abort_run "terminated during mix compile in app-phoenix"' TERM
if ! (cd "$root/app-phoenix" && scrubbed $ecto_env mix compile) >> "$work/ecto/prove.log" 2>&1; then
  abort_run "mix compile failed in app-phoenix (see ${work#"$root/"}/ecto/prove.log)"
fi
[ "${picked+set}" != set ] || : > "$summary"
[ "${picked+set}" != set ] || [ -n "$shard" ] || : > "$work/ecto/templates.used"

run_check() {
  echo "== start $(date -u +%s) $1" >> "$3"
  if line="$("$root/scripts/schema_parity/ecto_check.sh" "$1" 2>> "$3")"; then
    status=0
  else
    status=1
    [ -n "$line" ] || line="$1 FAIL error (see ${work#"$root/"}/ecto/prove.log)"
  fi
  echo "== end $(date -u +%s) $1 $status" >> "$3"
  echo "$line" | tee -a "$2"
}

run_lane() {
  trap - TERM
  lane="$1"
  shift
  index=0
  for check in "$@"; do
    index=$((index + 1))
    mkdir "$lanes/claim.$index" 2>/dev/null || continue
    run_check "$check" "$lanes/summary.$lane" "$lanes/log.$lane"
  done
}

lanes="$(mktemp -d "$work/ecto/.lanes.XXXXXX")" || abort_run "could not create a lane directory under $work/ecto"
trap 'cat "$lanes"/log.* >> "$work/ecto/prove.log" 2>/dev/null; rm -rf "$lanes"' EXIT
phase="while running the checks"
trap terminated TERM
printf '%s\n' "$@" > "$lanes/order"
parallel="$(grep -v '^contended:' "$lanes/order")"
lane=1
while [ "$lane" -le "$jobs" ]; do
  run_lane "$lane" $parallel &
  lane=$((lane + 1))
done
wait
for check in $(grep '^contended:' "$lanes/order"); do
  (trap - TERM; run_check "$check" "$lanes/summary.serial" "$lanes/log.serial") &
  wait $!
done
failed="$(awk -v summary="$summary" '
  { file = FILENAME; sub(/.*\//, "", file) }
  file ~ /^log\./ { if ($1 == "==" && $2 == "end") status[$4] = $5; next }
  file ~ /^summary\./ { lines[$1] = lines[$1] $0 "\n"; next }
  {
    if ($0 in lines) printf "%s", lines[$0] >> summary; else print $0 " FAIL no result" >> summary
    if (!($0 in lines) || status[$0] != "0") failed++
  }
  END { print failed + 0 }' "$lanes"/log.* "$lanes"/summary.* "$lanes/order")" || failed="$#"
phase="while dropping the stale scratch databases"
if [ "${picked+set}" = set ] && [ -z "$shard" ] && ! prune_databases; then
  echo "could not drop the stale scratch databases" >&2
fi
echo "ran $# checks, $failed failed"
[ "$failed" -eq 0 ]
