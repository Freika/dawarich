#!/bin/sh

sanitize_integer_env() {
  _name="$1"
  _default="$2"
  eval "_value=\${$_name:-}"

  case "$_value" in
    '' | auto) ;;
    *[!0-9]*)
      echo "⚠️ $_name='$_value' is not an integer (compose variable interpolation may have failed) — falling back to $_default" >&2
      eval "export $_name=$_default"
      ;;
  esac

  unset _name _default _value
}

env_value_is_truthy() {
  case "$(printf '%s' "$1" | tr -d "\"'" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes | on | t) return 0 ;;
  esac

  return 1
}

warn_if_development_env() {
  if [ "${RAILS_ENV:-${RACK_ENV:-development}}" = "development" ] && env_value_is_truthy "${SELF_HOSTED-true}"; then
    cat >&2 <<'EOF'
⚠️ Dawarich is running with RAILS_ENV=development ⚠️
Development mode is meant for working on Dawarich itself: code is loaded on
demand and reloaded when it changes, and every SQL query is logged at debug
level together with the line of code that ran it.

Self-hosted instances should run with RAILS_ENV=production, the default in
docker/docker-compose.yml since Dawarich 1.3.0. Compose files from earlier
versions default to development, so set RAILS_ENV=production explicitly for
both the app and the Sidekiq container.

Read this before switching an existing instance:
https://dawarich.app/docs/self-hosting/environment-variables/#switching-an-existing-instance-to-production
EOF
  fi
}
