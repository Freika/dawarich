// Replay HUD, implementing the "Replay Frames" design: broadcast chrome in
// the top and bottom safe bands (map clear in the middle third), a progress
// timeline with the playhead's recorded date, and a summary frame that fades
// in for the final hold. All sizes derive from the design's 620px reference
// frame via u = min(width, height) / 100 (design px ÷ 6.2).
import { hexToRgba, relativeLuminance } from "video_studio/color_util"
import {
  dayNumber,
  dayTotal,
  formatClockDate,
  formatDateRange,
  formatShortDate,
  splitDistance,
} from "video_studio/hud_format"
import { timeAtFraction } from "video_studio/route_clock"

// Families are supplied by the caller (hud_fonts loads the app's self-hosted
// faces and hands their family names back), so the HUD never reaches for a
// webfont CDN. The stacks below are the fallbacks if a face fails to load.
const MONO_FALLBACK = "ui-monospace, SFMono-Regular, Menlo, monospace"
const SANS_FALLBACK =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, sans-serif'
const INK = (a) => `rgba(255, 255, 255, ${a})`

// Type scale in u (u = min(width, height) / 100). The inherited numbers came
// from a 620px design frame; blown up to 1080x1920 and watched at phone size
// the secondary tier landed under 2% of the short edge, which is unreadable.
// Everything below the headline figures is lifted to about 2.5%.
const SIZE = {
  meta: 2.7, // playhead date, day counter, summary date range
  label: 2.4, // DISTANCE / OF TOTAL / footer dates
  tagline: 2.5,
  figure: 8.7, // live distance — already reads, kept as authored
  unit: 3.2,
  percent: 3.4,
  summaryFigure: 14.2,
  summaryUnit: 4.84,
  summaryLine: 3.4,
  watermark: 2.9,
}

// White-on-scrim opacities. The inherited 0.34-0.5 tier was illegible over a
// pale basemap; these hold up in both directions.
const INK_PRIMARY = 0.95
const INK_SECONDARY = 0.82
const INK_TERTIARY = 0.7

function text(
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
  } catch {
    // Older engines without canvas letterSpacing render slightly tighter.
  }
  ctx.fillText(str, x, y)
  try {
    ctx.letterSpacing = "0px"
  } catch {
    // Same fallback as above.
  }
}

// `weight` scales every stop: 1 on a white map, far less on a dark one. The
// scrim exists to keep white HUD text legible, so a map that is already dark
// needs only enough to separate text from detail.
function scrim(ctx, width, height, stops, alpha, weight = 1) {
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

function roundedRect(ctx, x, y, w, h, r) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

// The footer packs the start date, the centred credit and the end date onto one
// line. The credit is never dropped — it is the attribution — so when the three
// would collide this shrinks that row's type just enough to fit. MAX_HUD_SCALE
// is set below the measured collision point, so in practice this returns 1 and
// exists to hold the guarantee if a font falls back to a wider stack.
//
// Letter-spacing is added back by hand: measureText omits it on some engines,
// and under-measuring here would let strings overlap.
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

function replayChrome(ctx, opts) {
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

function summaryFrame(ctx, opts) {
  const {
    width,
    height,
    u,
    stats,
    units,
    accent,
    clock,
    fonts,
    labels,
    watermark,
  } = opts
  const { MONO, SANS } = fonts
  const inset = u * 4.8

  const footerBase = height - inset
  const dividerY = footerBase - u * 2.6 - u * 3.55
  const sublineBase = clock ? dividerY - u * 3.55 : dividerY - u * 2.4
  const numBase = clock ? sublineBase - u * 5.2 : sublineBase

  const distance = splitDistance(stats?.distanceM ?? 0, units)
  if (clock) {
    text(
      ctx,
      formatDateRange(clock.startTs, clock.endTs),
      inset,
      numBase - u * 13.4,
      {
        font: `700 ${u * SIZE.meta}px ${MONO}`,
        color: accent,
        ls: u * SIZE.meta * 0.22,
      },
    )
  }
  text(ctx, distance.value, inset, numBase, {
    font: `700 ${u * SIZE.summaryFigure}px ${MONO}`,
    color: "#fff",
    ls: -(u * SIZE.summaryFigure * 0.03),
  })
  ctx.font = `700 ${u * SIZE.summaryFigure}px ${MONO}`
  const numW = ctx.measureText(distance.value).width
  text(ctx, distance.unit, inset + numW + u * 1.6, numBase, {
    font: `500 ${u * SIZE.summaryUnit}px ${SANS}`,
    color: INK(0.6),
  })
  if (clock) {
    text(
      ctx,
      labels.travelledOver(dayTotal(clock.startTs, clock.endTs)),
      inset,
      sublineBase,
      {
        font: `500 ${u * SIZE.summaryLine}px ${SANS}`,
        color: INK(INK_SECONDARY),
      },
    )
  }

  ctx.fillStyle = INK(0.13)
  ctx.fillRect(inset, dividerY, width - inset * 2, 1)

  if (watermark) {
    ctx.fillStyle = accent
    ctx.beginPath()
    ctx.arc(inset + u * 0.72, footerBase - u * 0.8, u * 0.72, 0, Math.PI * 2)
    ctx.fill()
    text(ctx, watermark, inset + u * 2.9, footerBase, {
      font: `500 ${u * SIZE.watermark}px ${SANS}`,
      color: INK(INK_PRIMARY),
    })
  }
  text(ctx, labels.tagline, width - inset, footerBase, {
    font: `400 ${u * SIZE.tagline}px ${MONO}`,
    color: INK(INK_TERTIARY),
    ls: u * SIZE.tagline * 0.14,
    align: "right",
  })
}

export function drawHud(ctx, options) {
  const {
    width,
    height,
    fraction,
    outroProgress,
    clock,
    families,
    themeBg,
    hudScale,
  } = options
  // hudScale multiplies u, so the whole HUD — type, insets, the progress rail —
  // scales as one unit and the composition holds at any size.
  const u = (Math.min(width, height) / 100) * (hudScale || 1)
  const playheadTs = clock ? timeAtFraction(clock, fraction) : null
  const fonts = {
    MONO: `"${families?.mono ?? "monospace"}", ${MONO_FALLBACK}`,
    SANS: `"${families?.sans ?? "sans-serif"}", ${SANS_FALLBACK}`,
  }
  // A near-black basemap keeps a quarter of the wash; a white one keeps all
  // of it. Without this the darkest themes render as a black rectangle.
  const scrimWeight = 0.25 + 0.75 * relativeLuminance(themeBg ?? "#ffffff")
  const opts = { ...options, u, playheadTs, fonts }

  if (outroProgress < 1) {
    scrim(
      ctx,
      width,
      height,
      [
        [0, 0.72],
        [0.26, 0],
        [0.52, 0],
        [1, 0.86],
      ],
      1 - outroProgress,
      scrimWeight,
    )
  }
  if (outroProgress > 0) {
    scrim(
      ctx,
      width,
      height,
      [
        [0, 0.55],
        [0.3, 0.25],
        [0.74, 0.9],
        [1, 0.97],
      ],
      outroProgress,
      scrimWeight,
    )
  }

  ctx.save()
  if (outroProgress < 1) {
    ctx.globalAlpha = 1 - outroProgress
    replayChrome(ctx, opts)
  }
  ctx.restore()

  ctx.save()
  if (outroProgress > 0) {
    ctx.globalAlpha = outroProgress
    summaryFrame(ctx, opts)
  }
  ctx.restore()
}
