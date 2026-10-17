import { hexToRgba } from "./color_util.js"
import {
  dayNumber,
  dayTotal,
  formatClockDate,
  formatShortDate,
  splitDistance,
} from "./hud_format.js"

export const MONO_FALLBACK = "ui-monospace, SFMono-Regular, Menlo, monospace"
export const SANS_FALLBACK =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, sans-serif'
export const INK = (a) => `rgba(255, 255, 255, ${a})`

export const SIZE = {
  meta: 2.7,
  label: 2.4,
  tagline: 2.5,
  figure: 8.7,
  unit: 3.2,
  percent: 3.4,
  summaryFigure: 14.2,
  summaryUnit: 4.84,
  summaryLine: 3.4,
  watermark: 2.9,
}

export const INK_PRIMARY = 0.95
export const INK_SECONDARY = 0.82
export const INK_TERTIARY = 0.7

export function text(
  ctx,
  str,
  x,
  y,
  { font, color, ls = 0, align = "left", baseline = "alphabetic" },
) {
  ctx.font = font
  ctx.fillStyle = color
  ctx.textAlign = align
  ctx.textBaseline = baseline
  try {
    ctx.letterSpacing = `${ls}px`
  } catch {}
  ctx.fillText(str, x, y)
  try {
    ctx.letterSpacing = "0px"
  } catch {}
}

export function scrim(ctx, width, height, stops, alpha, weight = 1) {
  const gradient = ctx.createLinearGradient(0, 0, 0, height)
  for (const [at, a] of stops) {
    gradient.addColorStop(at, `rgba(6, 6, 8, ${(a * weight).toFixed(3)})`)
  }
  ctx.save()
  ctx.globalAlpha = alpha
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, width, height)
  ctx.restore()
}

export function roundedRect(ctx, x, y, w, h, r) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function footerTypeScale(ctx, { width, u, dateFont, clock, watermark }) {
  if (!clock || !watermark) return 1

  ctx.font = dateFont
  const tracking = u * SIZE.label * 0.12
  const advance = (value) =>
    ctx.measureText(value).width + tracking * String(value).length

  const centre = advance(watermark)
  const flank = Math.max(
    advance(formatShortDate(clock.startTs)),
    advance(formatShortDate(clock.endTs)),
  )
  const gap = u * 1.6
  const available = width / 2 - u * 3.9 - gap
  const needed = centre / 2 + flank
  if (needed <= available) return 1

  return Math.max(0.5, available / needed)
}

export function replayChrome(ctx, opts) {
  const {
    width,
    height,
    u,
    fraction,
    distanceM,
    units,
    accent,
    clock,
    playheadTs,
    fonts,
    labels,
    watermark,
  } = opts
  const { MONO, SANS } = fonts
  const inset = u * 3.9

  if (clock && playheadTs != null) {
    text(ctx, formatClockDate(playheadTs), inset, inset, {
      font: `400 ${u * SIZE.meta}px ${MONO}`,
      color: INK(INK_PRIMARY),
      ls: u * SIZE.meta * 0.18,
      baseline: "top",
    })
    const day = String(dayNumber(clock.startTs, playheadTs)).padStart(2, "0")
    const total = String(dayTotal(clock.startTs, clock.endTs)).padStart(2, "0")
    text(ctx, `${labels.day} ${day} / ${total}`, inset, inset + u * 3.7, {
      font: `400 ${u * SIZE.meta}px ${MONO}`,
      color: INK(INK_TERTIARY),
      ls: u * SIZE.meta * 0.1,
      baseline: "top",
    })
  }

  const datesBase = height - inset
  const trackY = datesBase - u * SIZE.label - u * 1.6 - u * 0.48
  const numBase = trackY - u * 2.6

  const footerScale = footerTypeScale(ctx, {
    width,
    u,
    dateFont: `400 ${u * SIZE.label}px ${MONO}`,
    clock,
    watermark,
  })
  const footerPx = u * SIZE.label * footerScale
  const dateFont = `400 ${footerPx}px ${MONO}`
  if (clock) {
    text(ctx, formatShortDate(clock.startTs), inset, datesBase, {
      font: dateFont,
      color: INK(INK_TERTIARY),
      ls: footerPx * 0.12,
    })
    text(ctx, formatShortDate(clock.endTs), width - inset, datesBase, {
      font: dateFont,
      color: INK(INK_TERTIARY),
      ls: footerPx * 0.12,
      align: "right",
    })
  }
  if (watermark) {
    text(ctx, watermark, width / 2, datesBase, {
      font: dateFont,
      color: INK(INK_SECONDARY),
      ls: footerPx * 0.12,
      align: "center",
    })
  }

  const trackW = width - inset * 2
  ctx.fillStyle = INK(0.14)
  roundedRect(ctx, inset, trackY, trackW, u * 0.48, u * 0.24)
  ctx.fill()
  if (fraction > 0) {
    ctx.fillStyle = accent
    roundedRect(
      ctx,
      inset,
      trackY,
      Math.max(u * 0.48, trackW * fraction),
      u * 0.48,
      u * 0.24,
    )
    ctx.fill()
  }
  const headX = inset + trackW * fraction
  const headY = trackY + u * 0.24
  ctx.fillStyle = hexToRgba(accent, 0.35)
  ctx.beginPath()
  ctx.arc(headX, headY, u * 0.72 + u * 0.48, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = "#fff"
  ctx.beginPath()
  ctx.arc(headX, headY, u * 0.72, 0, Math.PI * 2)
  ctx.fill()

  text(ctx, labels.distance, inset, numBase - u * 9.2, {
    font: `400 ${u * SIZE.label}px ${MONO}`,
    color: INK(INK_SECONDARY),
    ls: u * SIZE.label * 0.2,
  })
  const distance = splitDistance(distanceM, units)
  text(ctx, distance.value, inset, numBase, {
    font: `700 ${u * SIZE.figure}px ${MONO}`,
    color: "#fff",
    ls: -(u * SIZE.figure * 0.02),
  })
  ctx.font = `700 ${u * SIZE.figure}px ${MONO}`
  const numW = ctx.measureText(distance.value).width
  text(ctx, distance.unit, inset + numW + u * 1.1, numBase, {
    font: `500 ${u * SIZE.unit}px ${SANS}`,
    color: INK(INK_SECONDARY),
  })

  const valueBase = numBase - u * 1
  const labelBase = valueBase - u * 3.2

  text(ctx, labels.ofTotal, width - inset, labelBase, {
    font: `400 ${u * SIZE.label}px ${MONO}`,
    color: INK(INK_SECONDARY),
    ls: u * SIZE.label * 0.18,
    align: "right",
  })
  text(ctx, `${Math.round(fraction * 100)}%`, width - inset, valueBase, {
    font: `700 ${u * SIZE.percent}px ${MONO}`,
    color: accent,
    align: "right",
  })
}
