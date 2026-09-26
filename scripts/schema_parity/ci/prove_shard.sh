#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
prove="$root/scripts/schema_parity/ecto_prove.sh"
out="$work/nightly"
shard="${SHARD:?}/${SHARDS:?}"
mkdir -p "$out"
rm -f "$work"/ecto/summary*.txt "$out"/*
"$prove" --shard "$shard" --list > "$out/list.txt" || exit 2
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/sp-prove-shard.XXXXXX")" || exit 2
trap 'rm -rf "$tmpd"' EXIT
code="$(code_key)" || exit 2
references() {
  find "$work/ecto/ref" -name '*.status' 2>/dev/null | LC_ALL=C sort
}
references > "$out/refs.before"
started="$(date -u +%s)"
{
  timeout -k 60 160m "$prove" --shard "$shard" --jobs 2 all 2>&1
  echo $? > "$out/proof.exit"
} | tee "$out/proof.out"
finished="$(date -u +%s)"
references > "$out/refs.after"
status="$(cat "$out/proof.exit")"
reused="$(grep -c -- "-$code\.status\$" "$out/refs.before")"
computed="$(comm -13 "$out/refs.before" "$out/refs.after" | wc -l | tr -d ' ')"
printf 'exit=%s\nstarted=%s\nfinished=%s\nrefs_reused=%s\nrefs_computed=%s\n' \
  "$status" "$started" "$finished" "$reused" "$computed" > "$out/proof.env"
rm -f "$out/refs.before" "$out/refs.after" "$out/proof.exit"
exit "$status"
