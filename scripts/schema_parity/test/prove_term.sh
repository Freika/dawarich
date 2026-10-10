#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
lib="$root/scripts/schema_parity"
prove="$lib/ecto_prove.sh"
shell="${1:-}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-prove-term.XXXXXX")"
work="$scratch/work"
run="sp-term-$$"
template_query="FROM pg_database WHERE datname = 'sp_t_"
failures=0

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

cleanup() {
  [ ! -s "$scratch/hang.pids" ] || kill $(cat "$scratch/hang.pids") 2>/dev/null
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

gnu_timeout=""
for candidate in timeout gtimeout; do
  if "$candidate" --version 2>/dev/null | grep -q 'GNU coreutils'; then
    gnu_timeout="$candidate"
    break
  fi
done

mkdir -p "$scratch/bin" "$scratch/hangbin"
cat > "$scratch/bin/docker" <<EOF
#!/bin/sh
echo "\$*" >> "$scratch/docker.log"
case "\$*" in
  *"SHOW server_version_num"*) echo 170005; exit 0 ;;
esac
if [ -n "\${FAKE_HANG_ON:-}" ]; then
  case "\$*" in
    *"\$FAKE_HANG_ON"*)
      seen=\$(cat "$scratch/hang.count" 2>/dev/null || echo 0)
      echo \$((seen + 1)) > "$scratch/hang.count"
      [ "\$seen" -lt "\${FAKE_HANG_SKIP:-0}" ] || { echo \$\$ >> "$scratch/hang.pids"; exec sleep 60; }
      ;;
  esac
fi
exit 1
EOF
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/mix"
cp "$scratch/bin/docker" "$scratch/hangbin/docker"
printf '#!/bin/sh\necho $$ >> "%s"\nexec sleep 60\n' "$scratch/hang.pids" > "$scratch/hangbin/mix"
chmod +x "$scratch/bin/docker" "$scratch/bin/mix" "$scratch/hangbin/docker" "$scratch/hangbin/mix"

fake_root="$scratch/root"
mkdir -p "$fake_root/scripts/schema_parity" "$fake_root/app-phoenix"
for file in ecto_prove.sh lib.sh ecto_lib.sh ecto_template.sh; do
  cp "$lib/$file" "$fake_root/scripts/schema_parity/$file"
done
echo 'puts %w[fresh upgrade:0.37.2]' > "$fake_root/scripts/schema_parity/list_checks.rb"
printf '#!/bin/sh\necho "$1 ok"\n' > "$fake_root/scripts/schema_parity/ecto_check.sh"
chmod +x "$fake_root/scripts/schema_parity/ecto_check.sh"

harness() {
  bindir="$1"
  shift
  env PATH="$bindir:$PATH" LANG=en_US.UTF-8 SP_PG_MAJOR=17 SP_DB_CONTAINER="$run-db" SP_DB_PORT=1 \
    SP_REDIS_CONTAINER="$run-redis" SP_REDIS_PORT=2 SP_NETWORK="$run" SP_WORK="$work" "$@"
}

fresh_case() {
  [ ! -s "$scratch/hang.pids" ] || kill $(cat "$scratch/hang.pids") 2>/dev/null
  rm -rf "$work" "$scratch/hang.pids" "$scratch/hang.count" "$scratch/docker.log" "$scratch/pid"
}

launch() {
  bindir="$1"
  shift
  harness "$bindir" sh -c 'echo $$ > "$0"; exec "$@"' "$scratch/pid" "$@" >> "$scratch/launch.out" 2>&1 &
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

hung() { [ -s "$scratch/hang.pids" ]; }
exited() { ! kill -0 "$1" 2>/dev/null; }
all_exited() { for pid in "$@"; do exited "$pid" || return 1; done; }
no_scratch_dbs_left() { ! ls -d "$work"/.tmp.* >/dev/null 2>&1; }
summary() { cat "$work/ecto/summary.txt" 2>&1; }

finish() {
  [ ! -s "$scratch/hang.pids" ] || kill $(cat "$scratch/hang.pids") 2>/dev/null
  wait_until 30 all_exited "$@"
  verdict $? "every process of the run is gone afterwards"
  wait_until 30 no_scratch_dbs_left
  verdict $? "the interrupted check released its scratch databases"
}

if [ -n "$gnu_timeout" ]; then pass "GNU timeout is available as $gnu_timeout"; else flunk "GNU timeout is not installed"; fi

fresh_case
launch "$scratch/bin" env FAKE_HANG_ON="$template_query" "$gnu_timeout" -k 30 600 $shell "$prove" --jobs 1 upgrade:0.37.2
wait_until 120 hung
verdict $? "the lane's check reached its first docker exec"
kill -TERM "$(cat "$scratch/pid")"
wait "$launched"
status=$?
[ "$status" -eq 2 ]
verdict $? "a TERM from GNU timeout in the lanes phase exits 2 (exit $status)"
[ "$(summary)" = "ABORTED terminated while running the checks (unfinished: upgrade:0.37.2)" ]
verdict $? "it leaves an ABORTED line naming the unfinished check ($(summary))"
finish $(cat "$scratch/hang.pids")

fresh_case
launch "$scratch/bin" env FAKE_HANG_ON="$template_query" $shell "$prove" --jobs 1 contended:1.10.1:points
wait_until 120 hung
verdict $? "the serial contended check reached its first docker exec"
prove_pid="$(cat "$scratch/pid")"
children="$(pgrep -P "$prove_pid" | tr '\n' ' ')"
kill -TERM "$prove_pid"
wait_until 10 exited "$prove_pid"
verdict $? "a TERM to ecto_prove.sh alone during the serial phase does not wait for the hung check"
wait "$launched"
status=$?
[ "$status" -eq 2 ]
verdict $? "it exits 2 (exit $status)"
[ "$(summary)" = "ABORTED terminated while running the checks (unfinished: contended:1.10.1:points)" ]
verdict $? "it names the contended check ($(summary))"
finish $children

fresh_case
launch "$scratch/bin" env FAKE_HANG_ON="$template_query" $shell "$prove" --jobs 1 upgrade:0.37.2 fresh
wait_until 120 hung
verdict $? "the first of two checks in one lane reached its first docker exec"
prove_pid="$(cat "$scratch/pid")"
children="$(pgrep -P "$prove_pid" | tr '\n' ' ')"
kill -TERM "$prove_pid"
wait_until 10 exited "$prove_pid"
verdict $? "a TERM to ecto_prove.sh alone during the lanes phase returns at once"
wait "$launched"
status=$?
[ "$status" -eq 2 ] && [ "$(summary)" = "ABORTED terminated while running the checks (unfinished: upgrade:0.37.2)" ]
verdict $? "it exits 2 naming only the started check (exit $status: $(summary))"
finish $children
[ "$(grep -cF "$template_query" "$scratch/docker.log")" = 1 ]
verdict $? "the lane started no further check ($(grep -cF "$template_query" "$scratch/docker.log") template lookups)"

fresh_case
launch "$scratch/bin" env FAKE_HANG_ON="$template_query" FAKE_HANG_SKIP=1 "$gnu_timeout" -k 30 600 $shell "$prove" \
  --jobs 1 fresh upgrade:0.37.2
wait_until 120 hung
verdict $? "the second check reached its first docker exec after the first one failed"
kill -TERM "$(cat "$scratch/pid")"
wait "$launched"
status=$?
expected="$(printf '%s\n' "fresh FAIL error (see ${work#"$root/"}/ecto/prove.log)" \
  'ABORTED terminated while running the checks (unfinished: upgrade:0.37.2)')"
[ "$status" -eq 2 ] && [ "$(summary)" = "$expected" ]
verdict $? "a FAIL that finished before the TERM stays in the summary (exit $status: $(summary | tr '\n' '|'))"
finish $(cat "$scratch/hang.pids")

fresh_case
harness "$scratch/hangbin" "$gnu_timeout" -k 30 8 $shell "$prove" upgrade:0.37.2 > "$scratch/out" 2>&1
status=$?
[ "$status" -eq 124 ] && [ "$(summary)" = "ABORTED terminated during mix compile in app-phoenix" ]
verdict $? "GNU timeout expiring during mix compile leaves an ABORTED line (exit $status: $(summary))"
finish $(cat "$scratch/hang.pids")

fresh_case
harness "$scratch/bin" env FAKE_HANG_ON="datname ~" SP_EXEC_TIMEOUT=1 $shell "$fake_root/scripts/schema_parity/ecto_prove.sh" \
  --jobs 1 all > "$scratch/out" 2>&1
status=$?
[ "$status" -eq 2 ]
verdict $? "a docker exec timeout while dropping stale databases exits 2 (exit $status)"
expected="$(printf '%s\n' 'fresh ok' 'upgrade:0.37.2 ok' 'ABORTED terminated while dropping the stale scratch databases')"
[ "$(summary)" = "$expected" ]
verdict $? "it keeps the check lines and appends its ABORTED line ($(summary | tr '\n' '|'))"
grep -q 'timed out: docker exec' "$scratch/out"
verdict $? "the timed-out docker exec is named on stderr"

echo "$failures failed"
[ "$failures" -eq 0 ]
