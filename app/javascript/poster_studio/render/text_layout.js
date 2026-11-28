// Pure typography math for the poster footer, shared by the export canvas
// and the studio preview (which draws through the same overlay renderer).
// All sizes derive from the poster pixel width so any resolution agrees.

export function titleShrink(title, maxChars = 12) {
  const length = (title || "").trim().length
  if (length <= maxChars) return 1
  return Math.max(0.45, maxChars / length)
}

// The optional trip stats line ("27.4 km") must fit across the poster: a
// line too long for the width shrinks rather than run off the edges.
const STATS_MAX_WIDTH = 0.85

// Vertical stack anchored to the bottom margin, top-down:
//   TITLE / divider / subtitle / stats / coordinates
// Lines the caller leaves empty collapse out of the stack. `measure(text,
// size)` returns the drawn width of a line, so the stats line can be fitted.
export function layoutPosterText({
  width,
  height,
  title,
  subtitle,
  coords,
  stats,
  measure,
}) {
  const titleSize = Math.round(width * 0.075 * titleShrink(title))
  const subSize = Math.round(width * 0.026)
  const coordsSize = Math.round(width * 0.017)
  const statsSize = fitStatsSize(
    stats,
    Math.round(width * 0.02),
    width,
    measure,
  )
  const letterSpacing = Math.round(titleSize * 0.18)
  const margin = Math.round(height * 0.045)

  let cursor = height - margin
  const lines = {}

  if (coords) {
    lines.coordsY = cursor
    cursor -= Math.round(coordsSize * 1.9)
  }
  if (stats) {
    lines.statsY = cursor
    cursor -= Math.round(statsSize * 1.9)
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
    top: title ? cursor - titleSize : cursor,
    titleSize,
    subSize,
    coordsSize,
    statsSize,
    letterSpacing,
    dividerHalfWidth: Math.round(width * 0.12),
    dividerWidth: Math.max(1, Math.round(width * 0.0015)),
  }
}

function fitStatsSize(stats, size, width, measure) {
  if (!stats || !measure) return size
  const drawn = measure(stats, size)
  const maxWidth = width * STATS_MAX_WIDTH
  return drawn > maxWidth ? Math.floor((size * maxWidth) / drawn) : size
}

// "52.5200° N / 13.4050° E" from a {lat, lng} center.
export function formatCoords(center) {
  if (!center) return ""
  const lat = `${Math.abs(center.lat).toFixed(4)}° ${center.lat >= 0 ? "N" : "S"}`
  const lng = `${Math.abs(center.lng).toFixed(4)}° ${center.lng >= 0 ? "E" : "W"}`
  return `${lat} / ${lng}`
}
