const TILE_FILE_EXTENSIONS = [".png", ".jpg", ".jpeg", ".webp", ".mvt", ".pbf"]

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

  if (!hasXyz) {
    if (TILE_FILE_EXTENSIONS.some((extension) => path.endsWith(extension))) {
      return null
    }

    return isStyleDocumentLocation(trimmed) ? "style" : null
  }

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

// Matches Api::V1::SettingsController#style_json_url?: an absolute http(s) URL,
// or a root-relative path for a style served from this instance. A
// protocol-relative "//host/style.json" is neither, and the two validators must
// agree or the browser accepts a URL the API then rejects.
function isStyleDocumentLocation(url) {
  if (/^https?:\/\//i.test(url)) return true

  return url.startsWith("/") && !url.startsWith("//")
}

/**
 * Whether a MapLibre `error` event reports a failure of the style document
 * itself rather than one of the requests it spawns.
 * @param {Object} event - MapLibre ErrorEvent
 * @param {string} styleUrl - Style URL handed to setStyle
 * @returns {boolean} True when the style document is what failed
 */
export function styleDocumentFailed(event, styleUrl) {
  const failedUrl = event?.error?.url
  if (!failedUrl) return true

  return failedUrl === styleUrl
}
