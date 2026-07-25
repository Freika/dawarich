/**
 * Classify a custom basemap URL into the kind of MapLibre source it describes.
 * @param {string} url - Trimmed or untrimmed basemap URL
 * @returns {'style'|'raster'|'vector'|null} Classification, or null when unusable
 */
export function classifyBasemapUrl(url) {
  if (typeof url !== "string") return null

  const trimmed = url.trim()
  if (!trimmed) return null

  const path = trimmed.split(/[?#]/)[0].toLowerCase()

  const hasXyz =
    trimmed.includes("{z}") &&
    trimmed.includes("{x}") &&
    trimmed.includes("{y}")

  if (path.endsWith(".json") && !hasXyz) return "style"

  if (!hasXyz) return null

  if (
    path.endsWith(".png") ||
    path.endsWith(".jpg") ||
    path.endsWith(".jpeg") ||
    path.endsWith(".webp")
  ) {
    return "raster"
  }

  return "vector"
}
