export function createStyleControls({
  map,
  loadStyle,
  defaultStyleUrl,
  onFallback = () => {},
}) {
  let generation = 0
  let destroyed = false

  async function apply(url) {
    if (destroyed) return "stale"
    const current = ++generation
    try {
      const style = await loadStyle(url)
      if (current !== generation || destroyed) return "stale"
      map.setStyle(style)
      return "applied"
    } catch (_error) {
      if (current !== generation || destroyed || url === defaultStyleUrl)
        return "stale"
      const fallback = await loadStyle(defaultStyleUrl)
      if (current !== generation || destroyed) return "stale"
      map.setStyle(fallback)
      onFallback("custom_style_load_failed")
      return "fallback"
    }
  }

  function destroy() {
    destroyed = true
    generation++
  }

  return { apply, destroy }
}
