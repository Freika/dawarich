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

warn_if_development_env() {
  if [ "$RAILS_ENV" = "development" ] && [ "${SELF_HOSTED:-}" = "true" ]; then
    cat >&2 <<'EOF'
⚠️⚠️⚠️  RAILS_ENV=development on a self-hosted instance  ⚠️⚠️⚠️
Development mode skips eager loading and caching, and logs every SQL query
verbatim (with bind params) instead of Rails' compact production format.
Under real background-job load (imports, reverse geocoding, stats, visit
suggestions) this drives up memory and CPU far beyond what production mode
needs, and has caused Sidekiq to be OOM-killed and restarted on other
self-hosted instances — leaving gaps in recorded location data.

RAILS_ENV has defaulted to `production` in the bundled docker-compose.yml
since v1.3.0 (Feb 2026). If your compose file or .env still sets
RAILS_ENV=development from an older setup, remove that override (or set
RAILS_ENV=production and provide SECRET_KEY_BASE) unless you intend to
develop Dawarich itself.
See: https://dawarich.app/docs/self-hosting/environment-variables/
EOF
  fi
}
