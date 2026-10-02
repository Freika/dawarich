#!/bin/sh
set -eu
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
a="$1"
b="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proc='s/,"nth":{"ordinals":"#<Proc:[^"]*","ordinalized":"#<Proc:[^"]*"}//'
maps='del(.files[].mtime) | .files |= (to_entries | sort_by(.key) | from_entries) | .assets |= (to_entries | sort_by(.key) | from_entries)'
for side in a b; do
  eval dir=\$$side
  (cd "$dir" && find public/assets config/sprockets-manifest.json tmp/phoenix/i18n.json tmp/phoenix/achievements.json tmp/phoenix/importmap.json -type f) >"$work/$side.found"
  LC_ALL=C sort "$work/$side.found" >"$work/$side.list"
done
diff "$work/a.list" "$work/b.list" || { echo "the file sets differ" >&2; exit 1; }
status=0
while IFS= read -r f; do
  case "$f" in
    *.gz)
      { head -c 4 "$a/$f"; tail -c +9 "$a/$f"; } >"$work/x"
      { head -c 4 "$b/$f"; tail -c +9 "$b/$f"; } >"$work/y"
      cmp -s "$work/x" "$work/y" || { echo "gzip differs beyond its MTIME: $f"; status=1; }
      ;;
    config/sprockets-manifest.json)
      for side in a b; do
        eval dir=\$$side
        jq -cj . "$dir/$f" >"$work/$side.compact"
        cmp -s "$work/$side.compact" "$dir/$f" || { echo "manifest is not compact JSON: $side"; status=1; }
        jq -c "$maps" "$dir/$f" >"$work/$side.json"
      done
      cmp -s "$work/a.json" "$work/b.json" || { echo "manifest differs"; status=1; }
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
