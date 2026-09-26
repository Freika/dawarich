#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
report="$root/scripts/schema_parity/ci/nightly_report.rb"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-nightly-report.XXXXXX")"
failures=0
legs="pg14-shard1 pg14-shard2 pg17-shard1 pg17-shard2"
run_url="https://github.example/owner/repo/actions/runs/42"

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

listed='fresh
contended:1.14.1:points
refused:0.0.8
rows:1.7.6--unported-20260508193900
upgrade:0.37.2'
green='fresh ok
contended:1.14.1:points ok (failed@20260827200000)
refused:0.0.8 ok (refused below_floor 0.0.9)
rows:1.7.6--unported-20260508193900 ok (unported@20260508193900)
upgrade:0.37.2 ok'

every_other() { printf '%s\n' "$1" | awk -v k="$2" '(NR - 1) % 2 == k - 1'; }
green_of() { every_other "$green" "$1"; }

leg() {
  dir="$scratch/artifacts/$1"
  shard="${1#*-shard}"
  rm -rf "$dir"
  mkdir -p "$dir/nightly" "$dir/ecto"
  printf '%s\n' "${4:-$(every_other "$listed" "$shard")}" > "$dir/nightly/list.txt"
  printf 'exit=%s\nstarted=1000\nfinished=4723\nrefs_reused=3\nrefs_computed=1\n' "$2" > "$dir/nightly/proof.env"
  printf '%s\n' "$3" > "$dir/ecto/summary.$shard-2.txt"
  echo "total 5" > "$dir/inventory_preflight.txt"
}

all_green() {
  rm -rf "$scratch/artifacts"
  printf '%s\n' "$listed" > "$scratch/checks.txt"
  : > "$scratch/jobs.tsv"
  : > "$scratch/artifacts.tsv"
  id=100
  for name in $legs; do
    leg "$name" 0 "$(green_of "${name#*-shard}")"
    printf '%s\tcompleted\tsuccess\n' "$name" >> "$scratch/jobs.tsv"
    printf '%s\t%s\n' "$name" "$id" >> "$scratch/artifacts.tsv"
    id=$((id + 1))
  done
  printf 'nightly report\tin_progress\tnone\n' >> "$scratch/jobs.tsv"
}

aggregate() {
  output="$(LEGS="$legs" PROVE_RESULT="${1:-success}" RUN_URL="$run_url" LANG=en_US.UTF-8 \
    ruby "$report" report "$scratch/artifacts" "$scratch/jobs.tsv" "$scratch/artifacts.tsv" "$scratch/checks.txt" 2>&1)"
  status=$?
}

job_result() {
  sed "s/^$1\tcompleted\tsuccess$/$1\t$2/" "$scratch/jobs.tsv" > "$scratch/jobs.new"
  mv "$scratch/jobs.new" "$scratch/jobs.tsv"
}

all_green
aggregate
[ "$status" -eq 0 ]
verdict $? "four green shards pass (exit $status: $output)"
contains "$output" "| 14 | 1 | success | 3 / 3 | 1:02:03 | 3 / 1 | 0 | 0 | [pg14-shard1]($run_url/artifacts/100) |"
verdict $? "the table has PG major, shard, job, checks run, elapsed, references, failures, unported and the artifact link"
contains "$output" "| 17 | 2 | success | 2 / 2 |" && contains "$output" "pg17-shard2: rows:1.7.6--unported-20260508193900"
verdict $? "every shard has a row and the declared unported effects are named"

all_green
leg pg14-shard1 1 "$(green_of 1 | sed 's/^upgrade:0.37.2 ok$/upgrade:0.37.2 FAIL schema:12 rows:3/')"
job_result pg14-shard1 'completed\tfailure'
aggregate
[ "$status" -eq 1 ]
verdict $? "one FAIL line fails the report (exit $status)"
contains "$output" "pg14-shard1: upgrade:0.37.2: expected 'ok', actual 'FAIL schema:12 rows:3'"
verdict $? "it names the check with its expected and actual status"
contains "$output" "pg14-shard1: the harness exited 1" && contains "$output" "pg14-shard1: job completed, failure"
verdict $? "it names the harness exit and the job result"

all_green
rm "$scratch/artifacts/pg17-shard1/ecto/summary.1-2.txt"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg17-shard1: no summary file" && contains "$output" "pg17-shard1: 3 of 3 checks have no summary line"
verdict $? "a missing summary fails the report and says so ($output)"

all_green
leg pg17-shard2 124 "$(printf '%s\n' 'contended:1.14.1:points ok (failed@20260827200000)' \
  'ABORTED terminated while running the checks (unfinished: rows:1.7.6--unported-20260508193900)')"
aggregate
[ "$status" -eq 1 ]
verdict $? "an ABORTED line fails the report (exit $status)"
contains "$output" "pg17-shard2: ABORTED terminated while running the checks (unfinished: rows:1.7.6--unported-20260508193900)" \
  && contains "$output" "pg17-shard2: the harness timed out" && contains "$output" "pg17-shard2: 1 of 2 checks have no summary line"
verdict $? "it names the aborted run, the timeout and the checks without a line"

all_green
job_result pg14-shard1 'completed\tcancelled'
rm -rf "$scratch/artifacts/pg14-shard1"
grep -v '^pg14-shard1	' "$scratch/artifacts.tsv" > "$scratch/artifacts.new"
mv "$scratch/artifacts.new" "$scratch/artifacts.tsv"
aggregate cancelled
[ "$status" -eq 1 ]
verdict $? "a cancelled shard fails the report (exit $status)"
contains "$output" "pg14-shard1: job completed, cancelled" && contains "$output" "pg14-shard1: no artifact"
verdict $? "it names the cancelled job and its missing artifact"
contains "$output" "| 14 | 1 | cancelled | 0 / 0 |" && contains "$output" "matrix result: cancelled"
verdict $? "the cancelled shard still has a row and the matrix result is reported"
contains "$output" "pg14: 3 of 5 checks are in no shard: fresh, refused:0.0.8, upgrade:0.37.2"
verdict $? "the checks of the missing shard are named as uncovered"

all_green
grep -v '^pg17-shard2	' "$scratch/jobs.tsv" > "$scratch/jobs.new"
mv "$scratch/jobs.new" "$scratch/jobs.tsv"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg17-shard2: no job result"
verdict $? "a shard missing from the job list fails the report"

all_green
leg pg14-shard2 0 "$(green_of 2 | sed 's/ ok (failed@20260827200000)$/ ok/')"
aggregate
[ "$status" -eq 1 ] && contains "$output" "contended:1.14.1:points: expected 'ok (failed@20260827200000)', actual 'ok'"
verdict $? "an ok line that differs from its declared outcome fails the report"

all_green
leg pg17-shard1 0 "$(green_of 1; printf '%s\n' 'fresh ok' 'step:9.9.9 ok')"
aggregate
[ "$status" -eq 1 ] && contains "$output" "fresh: 2 summary lines" && contains "$output" "step:9.9.9: not in the --list selection"
verdict $? "duplicate and unlisted lines fail the report"

all_green
leg pg17-shard1 0 "$(green_of 1 | sed '1d'; echo 'fresh ok')"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg17-shard1: the summary is not in --list order"
verdict $? "a summary out of --list order fails the report"

all_green
aggregate failure
[ "$status" -eq 1 ] && contains "$output" "matrix result: failure"
verdict $? "a non-success matrix result fails the report even when every artifact is green"

all_green
rm "$scratch/jobs.tsv" "$scratch/artifacts.tsv"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg14-shard1: no job result" && contains "$output" "| none |"
verdict $? "missing job and artifact lists fail closed"

all_green
for shard in 1 2; do
  third="$(printf '%s\n' "$listed" | awk -v k="$shard" '(NR - 1) % 3 == k - 1')"
  leg "pg17-shard$shard" 0 "$(printf '%s\n' "$green" | awk -v k="$shard" '(NR - 1) % 3 == k - 1')" "$third"
done
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg17: 1 of 5 checks are in no shard: refused:0.0.8"
verdict $? "green shards that do not cover the full list fail the report ($output)"

all_green
leg pg14-shard2 0 "$(printf '%s\n' 'fresh ok'; green_of 2)" "$(printf '%s\n' fresh; every_other "$listed" 2)"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg14: 1 check is in more than one shard: fresh (pg14-shard1, pg14-shard2)"
verdict $? "overlapping shards fail the report"

all_green
leg pg14-shard2 0 "$(green_of 2; echo 'step:9.9.9 ok')" "$(every_other "$listed" 2; echo step:9.9.9)"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg14: 1 shard check is not in the full check list: step:9.9.9"
verdict $? "a shard check outside the full list fails the report"

all_green
rm "$scratch/checks.txt"
aggregate
[ "$status" -eq 1 ] && contains "$output" "no full check list"
verdict $? "a missing full check list fails closed"

all_green
echo 'fresh FAIL schema:1' > "$scratch/artifacts/pg14-shard1/ecto/summary.txt"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg14-shard1: 2 files match summary*.txt: summary.1-2.txt, summary.txt"
verdict $? "two summary files in one shard fail the report instead of one being picked"

all_green
echo 'started=1000' > "$scratch/artifacts/pg14-shard1/nightly/proof.env"
aggregate
[ "$status" -eq 1 ] && contains "$output" "pg14-shard1: the proof step stopped before the harness exited"
verdict $? "a proof record without an exit is named as an interrupted proof"

all_green
output="$(LANG=en_US.UTF-8 ruby "$report" leg "$scratch/artifacts/pg14-shard2" 2>&1)"
status=$?
[ "$status" -eq 0 ] && contains "$output" "2 of 2 checks, 1 unported"
verdict $? "leg mode passes a green shard ($output)"
leg pg14-shard1 1 "$(green_of 1 | sed 's/^fresh ok$/fresh FAIL ledger:1/')"
output="$(LANG=en_US.UTF-8 ruby "$report" leg "$scratch/artifacts/pg14-shard1" 2>&1)"
status=$?
[ "$status" -eq 1 ] && contains "$output" "fresh: expected 'ok', actual 'FAIL ledger:1'"
verdict $? "leg mode fails a shard with a FAIL line ($output)"
rm "$scratch/artifacts/pg14-shard1/nightly/proof.env"
output="$(LANG=en_US.UTF-8 ruby "$report" leg "$scratch/artifacts/pg14-shard1" 2>&1)"
[ $? -eq 1 ] && contains "$output" "no proof record"
verdict $? "leg mode fails a shard whose proof never ran"

echo "$failures failed"
[ "$failures" -eq 0 ]
