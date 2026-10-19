export function mapTranslate(getConfig) {
  return (key, bindings = {}) => {
    const labels = getConfig().uiLabels ?? {}
    const singular = bindings.count === 1 ? labels[`${key}.one`] : undefined
    return Object.entries(bindings).reduce(
      (text, [name, value]) => text.replaceAll(`{${name}}`, String(value)),
      singular ?? labels[key] ?? key,
    )
  }
}
