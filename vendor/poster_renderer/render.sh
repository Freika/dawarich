#!/bin/sh
# Entry point for Posters::NativeRenderer. In the production container the
# vendored Ubuntu libs live in /opt/mbgl-libs and the GLX backend needs a
# virtual X display (xvfb) — neither applies on a dev machine.
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d /opt/mbgl-libs ]; then
  export LD_LIBRARY_PATH="/opt/mbgl-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  exec xvfb-run -a node --import "$DIR/register.mjs" "$DIR/render.mjs" "$@"
fi
exec node --import "$DIR/register.mjs" "$DIR/render.mjs" "$@"
