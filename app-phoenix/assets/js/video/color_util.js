export const DAWARICH_BLUE = "#2563EB"

const FALLBACK_RGB = [37, 99, 235]

export function hexToRgba(hex, alpha) {
  const match = /^#([0-9a-f]{6})$/i.exec(hex || "")
  const [r, g, b] = match
    ? [0, 2, 4].map((i) => Number.parseInt(match[1].slice(i, i + 2), 16))
    : FALLBACK_RGB
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

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
