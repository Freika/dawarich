export function mapTranslate(getConfig) {
  return (key, bindings = {}) =>
    Object.entries(bindings).reduce(
      (text, [name, value]) => text.replaceAll(`{${name}}`, String(value)),
      getConfig().uiLabels?.[key] ?? key,
    )
}
