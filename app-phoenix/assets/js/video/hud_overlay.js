import { relativeLuminance } from "./color_util.js"
import {
  INK,
  INK_PRIMARY,
  INK_SECONDARY,
  INK_TERTIARY,
  MONO_FALLBACK,
  replayChrome,
  SANS_FALLBACK,
  SIZE,
  scrim,
  text,
} from "./hud_chrome.js"
import { dayTotal, formatDateRange, splitDistance } from "./hud_format.js"
import { timeAtFraction } from "./route_clock.js"

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
  const u = (Math.min(width, height) / 100) * (hudScale || 1)
  const playheadTs = clock ? timeAtFraction(clock, fraction) : null
  const fonts = {
    MONO: `"${families?.mono ?? "monospace"}", ${MONO_FALLBACK}`,
    SANS: `"${families?.sans ?? "sans-serif"}", ${SANS_FALLBACK}`,
  }
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
