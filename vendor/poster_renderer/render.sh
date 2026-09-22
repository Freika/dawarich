#!/bin/sh
# Entry point for Posters::NativeRenderer. In the production container the
# vendored Ubuntu libs live in /opt/mbgl-libs and the GLX backend needs a
# virtual X display (xvfb) — neither applies on a dev machine.
DIR="$(cd "$(dirname "$0")" && pwd)"
if node -e 'import("node:module").then(({ register }) => process.exit(typeof register === "function" ? 0 : 1))' \
  >/dev/null 2>&1; then
  set -- --import "$DIR/register.mjs" "$DIR/render.mjs" "$@"
else
  set -- --experimental-loader "$DIR/loader.mjs" "$DIR/render.mjs" "$@"
fi

if [ -d /opt/mbgl-libs ]; then
  export LD_LIBRARY_PATH="/opt/mbgl-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  exec xvfb-run -a node "$@"
fi
exec node "$@"
