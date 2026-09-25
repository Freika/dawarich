#!/bin/sh
# Cloud web, worker and release processes share an image, but no process should
# run migrations or seeds implicitly when a container restarts.
set -eu

unset BUNDLE_PATH
unset BUNDLE_BIN

if [ "$(id -u)" = 0 ]; then
  exec gosu 32767:32767 "$0" "$@"
fi

exec bundle exec "$@"
