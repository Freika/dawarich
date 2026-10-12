import { layoutPosterText } from "poster_studio/render/text_layout"

// Map data + product credit, drawn small and subtle along the bottom edge.
export const POSTER_ATTRIBUTION =
  "© OpenStreetMap contributors · https://dawarich.app"

function hexToRgba(hex, alpha) {
  const v = hex.replace("#", "")
  const n =
    v.length === 3
      ? v
          .split("")
          .map((c) => c + c)
          .join("")
      : v.padEnd(6, "0").slice(0, 6)
  const int = parseInt(n, 16)
  return `rgba(${(int >> 16) & 255}, ${(int >> 8) & 255}, ${int & 255}, ${alpha})`
}

function drawFades(ctx, width, height, color, strength) {
  const top = height * strength * 0.5
  const bottom = height * strength
  const topGrad = ctx.createLinearGradient(0, 0, 0, top)
  topGrad.addColorStop(0, hexToRgba(color, 0.9))
  topGrad.addColorStop(1, hexToRgba(color, 0))
  ctx.fillStyle = topGrad
  ctx.fillRect(0, 0, width, top)

  const botGrad = ctx.createLinearGradient(0, height - bottom, 0, height)
  botGrad.addColorStop(0, hexToRgba(color, 0))
  botGrad.addColorStop(1, hexToRgba(color, 0.97))
  ctx.fillStyle = botGrad
  ctx.fillRect(0, height - bottom, width, bottom)
}

// Centered fillText with wide tracking. ctx.letterSpacing adds the spacing
// after every glyph including the last, which shifts the visual center left
// by spacing/2 — compensate so the line stays centered.
function fillSpaced(ctx, text, x, y, spacing) {
  const supported = "letterSpacing" in ctx
  if (supported && spacing > 0) {
    ctx.letterSpacing = `${spacing}px`
    ctx.fillText(text, x + spacing / 2, y)
    ctx.letterSpacing = "0px"
  } else {
    ctx.fillText(text, x, y)
  }
}

function drawTitle(ctx, width, height, color, text, font) {
  const { title = "", subtitle = "", coords = "" } = text
  const layout = layoutPosterText({ width, height, title, subtitle, coords })
  ctx.textAlign = "center"
  ctx.fillStyle = color

  if (title) {
    ctx.font = `700 ${layout.titleSize}px ${font}`
    fillSpaced(
      ctx,
      title.toUpperCase(),
      width / 2,
      layout.titleY,
      layout.letterSpacing,
    )
  }
  if (subtitle) {
    ctx.strokeStyle = color
    ctx.globalAlpha = 0.6
    ctx.lineWidth = layout.dividerWidth
    ctx.beginPath()
    ctx.moveTo(width / 2 - layout.dividerHalfWidth, layout.dividerY)
    ctx.lineTo(width / 2 + layout.dividerHalfWidth, layout.dividerY)
    ctx.stroke()
    ctx.globalAlpha = 1
    ctx.font = `400 ${layout.subSize}px ${font}`
    fillSpaced(
      ctx,
      subtitle.toUpperCase(),
      width / 2,
      layout.subY,
      Math.round(layout.subSize * 0.25),
    )
  }
  if (coords) {
    ctx.globalAlpha = 0.75
    ctx.font = `400 ${layout.coordsSize}px ${font}`
    fillSpaced(
      ctx,
      coords,
      width / 2,
      layout.coordsY,
      Math.round(layout.coordsSize * 0.2),
    )
    ctx.globalAlpha = 1
  }
}

// A small, low-key credit line hugging the bottom edge — sits below the
// title/coords stack, inside the bottom fade so it stays legible.
function drawAttribution(ctx, width, height, color, text, font) {
  if (!text) return
  const size = Math.round(width * 0.013)
  ctx.save()
  ctx.textAlign = "center"
  ctx.fillStyle = color
  ctx.globalAlpha = 0.5
  ctx.font = `400 ${size}px ${font}`
  fillSpaced(
    ctx,
    text,
    width / 2,
    height - Math.round(height * 0.017),
    Math.round(size * 0.15),
  )
  ctx.restore()
}

export function drawOverlay(
  canvas,
  {
    theme,
    title = "",
    subtitle = "",
    coords = "",
    font = "Helvetica, Arial, sans-serif",
    fadeStrength = 0.22,
    margin = 0,
    attribution = POSTER_ATTRIBUTION,
  },
) {
  const ctx = canvas.getContext("2d")
  const { width, height } = canvas

  if (margin > 0) {
    const m = Math.round(Math.min(width, height) * margin)
    ctx.fillStyle = theme.bg
    ctx.fillRect(0, 0, width, m)
    ctx.fillRect(0, height - m, width, m)
    ctx.fillRect(0, 0, m, height)
    ctx.fillRect(width - m, 0, m, height)
  }

  drawFades(ctx, width, height, theme.gradientColor, fadeStrength)
  if (title || subtitle || coords)
    drawTitle(ctx, width, height, theme.text, { title, subtitle, coords }, font)
  drawAttribution(ctx, width, height, theme.text, attribution, font)
  return canvas
}
