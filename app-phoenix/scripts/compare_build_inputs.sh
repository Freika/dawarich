#!/bin/sh
set -eu
a="$1"
b="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proc='s/,"nth":{"ordinals":"#<Proc:[^"]*","ordinalized":"#<Proc:[^"]*"}//'
for side in a b; do
  eval dir=\$$side
  (cd "$dir" && find public/assets config/sprockets-manifest.json tmp/phoenix/i18n.json tmp/phoenix/achievements.json tmp/phoenix/importmap.json -type f | LC_ALL=C sort) >"$work/$side.list"
done
diff "$work/a.list" "$work/b.list" || { echo "the file sets differ" >&2; exit 1; }
status=0
while IFS= read -r f; do
  case "$f" in
    *.gz)
      gzip -dc "$a/$f" >"$work/x"
      gzip -dc "$b/$f" >"$work/y"
      cmp -s "$work/x" "$work/y" || { echo "inflated bytes differ: $f"; status=1; }
      [ "$(head -c 4 "$a/$f" | od -An -tx1)" = "$(head -c 4 "$b/$f" | od -An -tx1)" ] || { echo "gzip header differs: $f"; status=1; }
      [ "$(dd if="$a/$f" bs=1 skip=8 count=2 2>/dev/null | od -An -tx1)" = "$(dd if="$b/$f" bs=1 skip=8 count=2 2>/dev/null | od -An -tx1)" ] || { echo "gzip flags differ: $f"; status=1; }
      ;;
    config/sprockets-manifest.json)
      [ "$(jq -S 'del(.files[].mtime)' "$a/$f")" = "$(jq -S 'del(.files[].mtime)' "$b/$f")" ] || { echo "manifest differs"; status=1; }
      ;;
    tmp/phoenix/i18n.json)
      sed "$proc" "$a/$f" >"$work/x"
      sed "$proc" "$b/$f" >"$work/y"
      cmp -s "$work/x" "$work/y" || { echo "i18n differs"; status=1; }
      ;;
    *)
      cmp -s "$a/$f" "$b/$f" || { echo "differs: $f"; status=1; }
      ;;
  esac
done <"$work/a.list"
exit "$status"
