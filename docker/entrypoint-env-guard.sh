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
