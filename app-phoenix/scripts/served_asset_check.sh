#!/bin/sh
set -eu
root="$1"
asset="$2"
base="$3"
host="$4"
built="$root$asset"
[ -s "$built" ] || { echo "not in the image, or empty: $built" >&2; exit 1; }
served="$(mktemp)"
trap 'rm -f "$served"' EXIT
curl -fsS -H "Host: $host" -o "$served" "$base$asset"
cmp -s "$served" "$built" || { echo "$base$asset is not the built file" >&2; exit 1; }
