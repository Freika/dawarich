#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
lib="$root/scripts/schema_parity"
shell="${1:-}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-prove-shard.XXXXXX")"
work="$scratch/work"
run="sp-shard-$$"
template_query="FROM pg_database WHERE datname = 'sp_t_"
failures=0

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

descendants() {
  for child in $(pgrep -P "$1"); do
    echo "$child"
    descendants "$child"
  done
}

leftovers=""
cleanup() {
  for pid in $leftovers $(cat "$scratch/hang.pids" 2>/dev/null); do kill -TERM "$pid" 2>/dev/null; done
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$scratch/bin"
cat > "$scratch/bin/docker" <<EOF
#!/bin/sh
case "\$*" in
  *"SHOW server_version_num"*) echo 170005; exit 0 ;;
  *"$template_query"*) echo \$\$ >> "$scratch/hang.pids"; exec sleep 60 ;;
esac
exit 1
EOF
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/mix"
chmod +x "$scratch/bin/docker" "$scratch/bin/mix"
if tail --version 2>/dev/null | grep -q 'GNU coreutils'; then
  :
elif command -v gtail >/dev/null; then
  ln -s "$(command -v gtail)" "$scratch/bin/tail"
fi

echo "exec ${shell:+$shell }scripts/schema_parity/ci/prove_shard.sh" > "$scratch/step.sh"

step() {
  step_root="$1"
  shift
  (
    cd "$step_root" || exit 1
    env PATH="$scratch/bin:$PATH" LANG=en_US.UTF-8 SP_PG_MAJOR=17 SP_DB_CONTAINER="$run-db" SP_DB_PORT=1 \
      SP_REDIS_CONTAINER="$run-redis" SP_REDIS_PORT=2 SP_NETWORK="$run" SP_WORK="$work" SHARD=1 SHARDS=67 "$@" \
      perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' sh -c 'echo $$ > "$0"; exec bash -e "$1"' "$scratch/pid" "$scratch/step.sh"
  ) > "$scratch/step.out" 2>&1 &
  launched=$!
}

wait_until() {
  ticks=$(($1 * 5))
  shift
  until "$@"; do
    ticks=$((ticks - 1))
    [ "$ticks" -gt 0 ] || return 1
    sleep 0.2
  done
}

both_lanes_hung() { [ "$(cat "$scratch/hang.pids" 2>/dev/null | wc -l)" -ge 2 ]; }
exited() { ! kill -0 "$1" 2>/dev/null; }
all_exited() { for pid in "$@"; do exited "$pid" || return 1; done; }
summary() { cat "$work/ecto/summary.1-67.txt" 2>&1; }
record() { sed -n "s/^$1=//p" "$work/nightly/proof.env" 2>/dev/null; }

fresh_case() {
  rm -rf "$work" "$scratch/hang.pids" "$scratch/pid"
  mkdir -p "$work"
}

finish() {
  wait_until 30 all_exited $leftovers
  verdict $? "every process of the step is gone afterwards"
  for pid in $leftovers; do kill -TERM "$pid" 2>/dev/null; done
  leftovers=""
}

aborted="ABORTED terminated while running the checks (unfinished: fresh rows:1.11.0--indexed)"
for signal in INT TERM; do
  fresh_case
  step "$root"
  wait_until 120 both_lanes_hung
  verdict $? "both lanes of the shard reached a docker exec ($signal case)"
  step_pid="$(cat "$scratch/pid")"
  leftovers="$(descendants "$step_pid" | tr '\n' ' ')"
  kill -"$signal" "$step_pid"
  wait_until 20 exited "$step_pid"
  verdict $? "SIG$signal to the step shell ends the step"
  wait "$launched"
  status=$?
  [ "$status" -eq 2 ] && [ "$(summary | tail -n 1)" = "$aborted" ]
  verdict $? "the harness wrote its ABORTED line and its exit reached the step (exit $status: $(summary | tr '\n' '|'))"
  [ "$(record exit)" = 2 ] && [ -n "$(record started)" ] && [ -n "$(record finished)" ]
  verdict $? "proof.env records the harness exit ($(tr '\n' ' ' < "$work/nightly/proof.env" 2>&1))"
  grep -q 'terminated while running the checks' "$work/nightly/proof.out"
  verdict $? "the harness output reached nightly/proof.out"
  finish
done

fresh_case
step "$root"
wait_until 120 both_lanes_hung
verdict $? "both lanes of the shard reached a docker exec (KILL case)"
step_pid="$(cat "$scratch/pid")"
leftovers="$(descendants "$step_pid" | tr '\n' ' ')"
guard="$(pgrep -P "$step_pid" -x timeout)"
kill -KILL "$step_pid"
wait "$launched"
[ -n "$guard" ] && kill -TERM "$guard"
[ -n "$(record started)" ] && [ -z "$(record exit)" ]
verdict $? "a killed step leaves a proof record without an exit ($(tr '\n' ' ' < "$work/nightly/proof.env" 2>&1))"
output="$(LANG=en_US.UTF-8 ruby "$lib/ci/nightly_report.rb" leg "$work" 2>&1)"
case "$output" in
  *"the proof step stopped before the harness exited"*) pass "the report names the interrupted proof" ;;
  *) flunk "the report names the interrupted proof ($output)" ;;
esac
finish

fake_root="$scratch/root"
code="$(printf '%040d' 7)"
old="$(printf '%040d' 6)"
hex() { printf '%040d' "$1"; }
mkdir -p "$fake_root/scripts/schema_parity/ci"
cp "$lib/lib.sh" "$fake_root/scripts/schema_parity/lib.sh"
cp "$lib/ci/prove_shard.sh" "$fake_root/scripts/schema_parity/ci/prove_shard.sh"
echo "code_key() { echo $code; }" > "$fake_root/scripts/schema_parity/ecto_lib.sh"
cat > "$fake_root/scripts/schema_parity/ecto_prove.sh" <<EOF
#!/bin/sh
case "\$*" in
  *--list*) printf '%s\n' fresh upgrade:0.37.2 rows:1.7.8~shifted contended:1.10.1:points ;;
  *)
    echo "\$*" > "\$SP_WORK/prove.args"
    touch "\$SP_WORK/ecto/ref/fresh.$(hex 2)-$code.status" "\$SP_WORK/ecto/ref/rows_1.7.8_shifted.$(hex 3)-$code.status"
    echo "ran 4 checks, 0 failed"
    ;;
esac
EOF
chmod +x "$fake_root/scripts/schema_parity/ecto_prove.sh" "$fake_root/scripts/schema_parity/ci/prove_shard.sh"
fresh_case
mkdir -p "$work/ecto/ref"
for ref in "upgrade_0.37.2.$(hex 1)-$code" "fresh.$(hex 0)-$code" "rows_1.7.8_shifted.$(hex 3)-$old" "step_9.9.9.$(hex 4)-$code"; do
  touch "$work/ecto/ref/$ref.status"
done
step "$fake_root"
wait "$launched"
status=$?
[ "$status" -eq 0 ] && [ "$(record refs_reused)" = 1 ] && [ "$(record refs_computed)" = 2 ]
verdict $? "only references the per-check key accepted count as reused (exit $status: $(tr '\n' ' ' < "$work/nightly/proof.env" 2>&1))"
[ "$(cat "$work/prove.args" 2>&1)" = "--jobs 2 --shard 1/67 all" ]
verdict $? "without arguments it proves shard SHARD of SHARDS ($(cat "$work/prove.args" 2>&1))"

echo "exec ${shell:+$shell }scripts/schema_parity/ci/prove_shard.sh upgrade:0.37.2 fresh" > "$scratch/step.sh"
fresh_case
mkdir -p "$work/ecto/ref"
step "$fake_root" SHARD= SHARDS=
wait "$launched"
status=$?
[ "$status" -eq 0 ] && [ "$(cat "$work/prove.args" 2>&1)" = "--jobs 2 upgrade:0.37.2 fresh" ]
verdict $? "with checks as arguments it proves exactly those, without SHARD or SHARDS (exit $status: $(cat "$work/prove.args" 2>&1))"
[ "$(tr '\n' ' ' < "$work/nightly/list.txt" 2>&1)" = "upgrade:0.37.2 fresh " ] && [ "$(record exit)" = 0 ] &&
  [ "$(record refs_computed)" = 2 ]
verdict $? "their list and proof record are written as for a shard ($(tr '\n' ' ' < "$work/nightly/proof.env" 2>&1))"

echo "$failures failed"
[ "$failures" -eq 0 ]
