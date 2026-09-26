#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
prove="$root/scripts/schema_parity/ecto_prove.sh"
out="$work/nightly"
mkdir -p "$out"
rm -f "$work"/ecto/summary*.txt "$out"/*
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" > "$out/list.txt"
else
  shard="${SHARD:?}/${SHARDS:?}"
  "$prove" --shard "$shard" --list > "$out/list.txt" || exit 2
  set -- --shard "$shard" all
fi
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/sp-prove-shard.XXXXXX")" || exit 2
trap 'rm -rf "$tmpd"' EXIT
code="$(code_key)" || exit 2
references() {
  find "$work/ecto/ref" -name '*.status' 2>/dev/null | LC_ALL=C sort
}
checks_of() {
  sed 's|.*/||; s/\.[0-9a-f]\{40\}-[0-9a-f]\{40\}\.status$//' | LC_ALL=C sort -u
}
references > "$tmpd/refs.before"
echo "started=$(date -u +%s)" > "$out/proof.env"
timeout -k 60 150m "$prove" --jobs 2 "$@" > "$out/proof.out" 2>&1 &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null' INT TERM
tail -f --pid="$pid" "$out/proof.out" &
wait "$pid"
status=$?
while kill -0 "$pid" 2>/dev/null; do
  wait "$pid"
  status=$?
done
wait
references > "$tmpd/refs.after"
tr ':+@~' '____' < "$out/list.txt" | LC_ALL=C sort -u > "$tmpd/listed"
grep -e "-$code\.status\$" "$tmpd/refs.before" | checks_of > "$tmpd/valid"
LC_ALL=C comm -13 "$tmpd/refs.before" "$tmpd/refs.after" > "$tmpd/new"
checks_of < "$tmpd/new" > "$tmpd/recomputed"
LC_ALL=C comm -12 "$tmpd/valid" "$tmpd/listed" | LC_ALL=C comm -23 - "$tmpd/recomputed" > "$tmpd/reused"
printf 'exit=%s\nfinished=%s\nrefs_reused=%s\nrefs_computed=%s\n' "$status" "$(date -u +%s)" \
  "$(wc -l < "$tmpd/reused" | tr -d ' ')" "$(wc -l < "$tmpd/new" | tr -d ' ')" >> "$out/proof.env"
exit "$status"
