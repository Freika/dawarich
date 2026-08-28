// Hex → rgba() strings for the line-gradient stops. Malformed input falls
// back to the Dawarich brand blue rather than crashing a render.
export const DAWARICH_BLUE = "#2563EB"

const FALLBACK_RGB = [37, 99, 235]

export function hexToRgba(hex, alpha) {
  const match = /^#([0-9a-f]{6})$/i.exec(hex || "")
  const [r, g, b] = match
    ? [0, 2, 4].map((i) => Number.parseInt(match[1].slice(i, i + 2), 16))
    : FALLBACK_RGB
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

// WCAG relative luminance, 0 (black) to 1 (white). The HUD reads it off the
// theme's background to decide how much scrim white text needs: a pale map
// needs the full dark wash to stay legible, a near-black one needs almost
// none — applying the same wash to both is what turns a dark theme's video
// into a black rectangle.
export function relativeLuminance(hex) {
  const match = /^#([0-9a-f]{6})$/i.exec(hex || "")
  const [r, g, b] = match
    ? [0, 2, 4].map((i) => Number.parseInt(match[1].slice(i, i + 2), 16))
    : FALLBACK_RGB
  const channel = (value) => {
    const c = value / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
}
