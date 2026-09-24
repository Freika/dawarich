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

summary="$work/ecto/summary.txt"
[ -z "$shard" ] || summary="$work/ecto/summary.$k-$n.txt"

abort_run() {
  echo "ABORTED $*" > "$summary"
  echo "$*" >&2
  exit 2
}

select_shard() {
  if [ -z "$shard" ]; then cat; else awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1'; fi
}

case "${1:-}" in
  --list)
    checks="$(list_checks)" || exit 2
    picked="$(printf '%s\n' "$checks" | select_shard)"
    [ -n "$picked" ] || { echo "no checks selected${shard:+ for shard $shard}" >&2; exit 2; }
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

if dotenv="$(local_dotenv)"; then
  abort_run "refusing to run: $dotenv exists and dotenv would load it into the Rails side only"
fi
if ! (cd "$root/app-phoenix" && scrubbed $ecto_env mix compile) >> "$work/ecto/prove.log" 2>&1; then
  abort_run "mix compile failed in app-phoenix (see tmp/schema_parity/ecto/prove.log)"
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
