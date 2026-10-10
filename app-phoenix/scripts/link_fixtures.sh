#!/bin/sh
set -eu
app=$(cd "$(dirname "$0")/.." && pwd)
e2e=${1:-${DAWARICH_E2E_REPO:-}}
[ -n "$e2e" ] || { echo "usage: $0 /path/to/e2e-dawarich-playwright (or set DAWARICH_E2E_REPO)" >&2; exit 64; }
source=$(cd "$e2e/phoenix-fixtures" && pwd)
target="$app/test/fixtures"
if [ -L "$target" ]; then rm "$target"; elif [ -e "$target" ]; then echo "$target exists and is not a link; move it away first" >&2; exit 1; fi
ln -s "$source" "$target"
echo "$target -> $source"
