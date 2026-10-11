const TILE_FILE_EXTENSIONS = [".png", ".jpg", ".jpeg", ".webp", ".mvt", ".pbf"]

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
    if (/[{}]/.test(trimmed)) return null

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
function isStyleDocumentLocation(url) {
  if (/^https?:\/\//i.test(url)) return true

  return url.startsWith("/") && !url.startsWith("//")
}

export function styleDocumentFailed(event, styleUrl) {
  const failedUrl = event?.error?.url
  if (!failedUrl) return true

  return failedUrl === styleUrl
}
