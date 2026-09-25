#!/bin/sh
# Cloud web, worker and release processes share an image, but no process should
# run migrations or seeds implicitly when a container restarts.
set -eu

unset BUNDLE_PATH
unset BUNDLE_BIN

if [ "$(id -u)" = 0 ]; then
  cloud_uid=32767
  cloud_gid=32767
  watched_dir="${APP_PATH:-/var/app}/tmp/imports/watched"

  # The named volume starts root-owned. The watcher must be able to read and
  # remove files placed there, including files restored during cutover.
  mkdir -p "$watched_dir"
  if [ "$(stat -c '%u:%g' "$watched_dir")" != "$cloud_uid:$cloud_gid" ]; then
    chown -R "$cloud_uid:$cloud_gid" "$watched_dir"
  fi
  exec gosu "$cloud_uid:$cloud_gid" "$0" "$@"
fi

exec bundle exec "$@"
