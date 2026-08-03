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

export function translate(key, values = {}) {
  translations ||= loadTranslations()
  let value = key.split(".").reduce((current, part) => current?.[part], translations)
  if (value && typeof value === "object" && values.count !== undefined) {
    value = value[Number(values.count) === 1 ? "one" : "other"]
  }
  if (typeof value !== "string") return key

  return value.replace(/%\{([^}]+)\}/g, (_match, name) => values[name] ?? `%{${name}}`)
}
