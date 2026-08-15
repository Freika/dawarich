let translations

function loadTranslations() {
  if (typeof document === "undefined") return {}
  const element = document.getElementById("i18n-translations")
  if (!element) return {}

  try {
    return JSON.parse(element.textContent)
  } catch (_error) {
    return {}
  }
}

function currentTranslations() {
  if (translations && Object.keys(translations).length > 0) return translations

  translations = loadTranslations()
  return translations
}

export function translate(key, values = {}) {
  let value = key
    .split(".")
    .reduce((current, part) => current?.[part], currentTranslations())
  if (value && typeof value === "object" && values.count !== undefined) {
    value = value[Number(values.count) === 1 ? "one" : "other"]
  }
  if (typeof value !== "string") return key

  return value.replace(
    /%\{([^}]+)\}/g,
    (_match, name) => values[name] ?? `%{${name}}`,
  )
}

export function formatNumber(value) {
  const locale =
    typeof document === "undefined" ? undefined : document.documentElement?.lang
  return new Intl.NumberFormat(locale || undefined).format(value)
}
