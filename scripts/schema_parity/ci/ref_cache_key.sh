#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/../../.." && pwd)"
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/sp-ref-key.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT
. "$root/scripts/schema_parity/lib.sh"
. "$root/scripts/schema_parity/ecto_lib.sh"
code="$(code_key)"
cd "$root"
find db/release_snapshots scripts/schema_parity/fixtures scripts/schema_parity/ecto_expectations.tsv -type f > "$tmpd/found"
LC_ALL=C sort "$tmpd/found" > "$tmpd/inputs"
git hash-object --no-filters --stdin-paths < "$tmpd/inputs" > "$tmpd/blobs"
{
  echo "code $code"
  paste "$tmpd/inputs" "$tmpd/blobs"
} > "$tmpd/cache.input"
checksum "$tmpd/cache.input"
