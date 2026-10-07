#!/bin/sh

validate_phoenix_lifecycle() {
  validate_cloud_drain_argv "$0" "$@"
  case "${DAWARICH_PHOENIX_LIFECYCLE-false}" in
    false) ;;
    true) ;;
    *)
      echo "DAWARICH_PHOENIX_LIFECYCLE must be true or false" >&2
      exit 1
      ;;
  esac
}

validate_cloud_drain_mode() {
  case "${DAWARICH_CLOUD_DRAIN_ONLY-false}" in
    false) return ;;
    true)
      if [ "${SELF_HOSTED-true}" = false ] &&
         [ "${DAWARICH_PHOENIX_LIFECYCLE-false}" = false ] &&
         [ -z "${DAWARICH_PROCESS_ROLE:-}" ]; then
        return
      fi
      echo "Cloud drain requires SELF_HOSTED=false and a source worker without native or idle mode" >&2
      ;;
    *) echo "DAWARICH_CLOUD_DRAIN_ONLY must be true or false" >&2 ;;
  esac
  exit 1
}

validate_cloud_drain_argv() {
  validate_cloud_drain_mode
  validate_native_admission
  [ "${DAWARICH_CLOUD_DRAIN_ONLY-false}" = true ] || return 0
  if [ "${1##*/}" = cloud-sidekiq-entrypoint.sh ]; then
    shift
    case "$#" in
      1) [ "$1" = sidekiq ] && return 0 ;;
      3) [ "$1" = sidekiq ] && [ "$2" = -C ] && [ "$3" = config/sidekiq.yml ] && return 0 ;;
    esac
  fi
  echo "Cloud drain permits only the source Sidekiq worker with its known configuration" >&2
  exit 1
}

validate_cloud_native_worker() {
  validate_native_admission
  phoenix_lifecycle_is_native || return 0
  [ "${SELF_HOSTED-true}" = false ] || return 0
  case "$#" in
    1) [ "$1" = sidekiq ] && return 0 ;;
    3) [ "$1" = sidekiq ] && [ "$2" = -C ] && [ "$3" = config/sidekiq.yml ] && return 0 ;;
  esac
  echo "Native Cloud worker requires the known Sidekiq compatibility command" >&2
  exit 1
}

validate_native_admission() {
  case "${DAWARICH_PHOENIX_LIFECYCLE-false}" in
    false | true) ;;
    *) echo "DAWARICH_PHOENIX_LIFECYCLE must be true or false" >&2; exit 1 ;;
  esac
  phoenix_lifecycle_is_native || return 0
  env_value_is_truthy "${SELF_HOSTED-true}" && return 0
  if [ "${SELF_HOSTED-true}" = false ] &&
     [ "${DAWARICH_CLOUD_DRAIN_ONLY-false}" = false ] &&
     [ -n "$(printf '%s' "${JWT_SECRET_KEY:-}" | tr -d '[:space:]')" ] &&
     printf '%s' "${MANAGER_URL:-}" | grep -Eq '^https://([A-Za-z0-9][A-Za-z0-9.-]*|\[[0-9A-Fa-f:]+\])(:[0-9]+)?$' &&
     cloud_session_url_is_direct; then
    case "${0##*/}" in
      web-entrypoint.sh | sidekiq-entrypoint.sh)
        echo "Native Cloud requires the Cloud web or worker entrypoint" >&2
        exit 1
        ;;
    esac
    return 0
  fi
  echo "Native lifecycle requires self-hosted mode" >&2
  exit 1
}

cloud_session_url_is_direct() {
  printf '%s' "${DATABASE_SESSION_URL:-}" |
    grep -Eq '^postgres(ql)?://([^/@[:space:]]+@)?([A-Za-z0-9][A-Za-z0-9.-]*|\[[0-9A-Fa-f:]+\])(:[0-9]+)?/[^/?#[:space:]]+(\?(sslmode=(disable|require|verify-ca|verify-full)|pool_mode=session|pooling_mode=session)(&(sslmode=(disable|require|verify-ca|verify-full)|pool_mode=session|pooling_mode=session))*)?$' || return 1
  case "${DATABASE_SESSION_URL%%\?*}" in
    *:6432/*) return 1 ;;
  esac
}

phoenix_lifecycle_is_native() {
  [ "${DAWARICH_PHOENIX_LIFECYCLE-false}" = true ] || [ "${DAWARICH_RAILS:-}" = off ]
}

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

if [ "${0##*/}" = sidekiq-entrypoint.sh ] &&
   ! env_value_is_truthy "${SELF_HOSTED-true}" && phoenix_lifecycle_is_native; then
  validate_phoenix_lifecycle "$@"
fi
