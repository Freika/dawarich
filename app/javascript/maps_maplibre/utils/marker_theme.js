const STROKE_BY_STYLE = {
  light: "#1e3a8a",
  white: "#1e3a8a",
  grayscale: "#1e3a8a",
  dark: "#ffffff",
  black: "#ffffff",
}

export function getMarkerStrokeColor(styleName) {
  return STROKE_BY_STYLE[styleName] ?? "#ffffff"
}

// Kept in sync with the timeline's rail dot by reading the same custom
// property both consume. MapLibre paint values must be literals, so the
// property is resolved once here rather than referenced in the expression.
const VISIT_MARKER_FALLBACK = "#38bdf8"

export function getVisitMarkerColor() {
  if (typeof document === "undefined") return VISIT_MARKER_FALLBACK

  const value = getComputedStyle(document.documentElement)
    .getPropertyValue("--visit-marker")
    .trim()

  return value || VISIT_MARKER_FALLBACK
}
