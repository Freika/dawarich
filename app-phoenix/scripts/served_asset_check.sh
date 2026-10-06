#!/bin/sh
set -eu
if [ "${1:-}" = --stylesheet ]; then
  shift
  root="$1"
  manifest="$2"
  base="$3"
  host="$4"
  command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
  logical="$(jq -er '.assets["tailwind.css"] | select(type == "string" and length > 0)' "$manifest")" || {
    echo "tailwind.css is missing from the native manifest" >&2; exit 1;
  }
  case "$logical" in /*|*..*|*\\*) echo "invalid native stylesheet path" >&2; exit 1 ;; esac
  asset="/assets/$logical"
else
  root="$1"
  asset="$2"
  base="$3"
  host="$4"
fi
built="$root$asset"
[ -s "$built" ] || { echo "not in the image, or empty: $built" >&2; exit 1; }
served="$(mktemp)"
trap 'rm -f "$served"' EXIT
curl -fsS -H "Host: $host" -o "$served" "$base$asset"
cmp -s "$served" "$built" || { echo "$base$asset is not the built file" >&2; exit 1; }
