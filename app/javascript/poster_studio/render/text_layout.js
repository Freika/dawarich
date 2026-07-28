// Pure typography math for the poster footer, shared by the export canvas
// and the studio preview (which draws through the same overlay renderer).
// All sizes derive from the poster pixel width so any resolution agrees.

export function titleShrink(title, maxChars = 12) {
  const length = (title || "").trim().length
  if (length <= maxChars) return 1
  return Math.max(0.45, maxChars / length)
}

// Vertical stack anchored to the bottom margin, top-down:
//   TITLE / divider / subtitle / coordinates
// Lines the caller leaves empty collapse out of the stack.
export function layoutPosterText({ width, height, title, subtitle, coords }) {
  const titleSize = Math.round(width * 0.075 * titleShrink(title))
  const subSize = Math.round(width * 0.026)
  const coordsSize = Math.round(width * 0.017)
  const letterSpacing = Math.round(titleSize * 0.18)
  const margin = Math.round(height * 0.045)

  let cursor = height - margin
  const lines = {}

  if (coords) {
    lines.coordsY = cursor
    cursor -= Math.round(coordsSize * 1.9)
  }
  if (subtitle) {
    lines.subY = cursor
    cursor -= Math.round(subSize * 1.5)
    lines.dividerY = cursor
    cursor -= Math.round(titleSize * 0.55)
  } else if (title) {
    cursor -= Math.round(titleSize * 0.25)
  }
  if (title) lines.titleY = cursor

  return {
    ...lines,
    titleSize,
    subSize,
    coordsSize,
    letterSpacing,
    dividerHalfWidth: Math.round(width * 0.12),
    dividerWidth: Math.max(1, Math.round(width * 0.0015)),
  }
}

// "52.5200° N / 13.4050° E" from a {lat, lng} center.
export function formatCoords(center) {
  if (!center) return ""
  const lat = `${Math.abs(center.lat).toFixed(4)}° ${center.lat >= 0 ? "N" : "S"}`
  const lng = `${Math.abs(center.lng).toFixed(4)}° ${center.lng >= 0 ? "E" : "W"}`
  return `${lat} / ${lng}`
}
