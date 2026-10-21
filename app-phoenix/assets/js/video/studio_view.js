import { studioQuery } from "../studios/dom.js"
import { formatLabel, themeName } from "./controls.js"
import { formatFor } from "./state.js"
import { buildStatRows } from "./video_stats.js"

export function renderSummary(root, ctx) {
  const { width, height } = formatFor(ctx.settings)
  renderStats(studioQuery(root, "[data-video-summary]"), {
    stats: ctx.stats,
    settings: ctx.settings,
    t: ctx.t,
    heading: ctx.t("summary", {
      format: formatLabel(root, ctx.settings),
      width,
      height,
      theme: ctx.themeTokens?.name ?? themeName(root, ctx.settings),
      seconds: ctx.settings.duration_sec,
    }),
  })
}

export function renderStats(target, { stats, settings, t, heading }) {
  if (!target || !stats) return
  const doc = target.ownerDocument ?? globalThis.document
  const make = (className, text) => {
    const node = doc
      ? doc.createElement("div")
      : { className: "", textContent: "" }
    node.className = className
    if (text !== undefined) node.textContent = text
    return node
  }
  const rows = buildStatRows(stats, settings.units, {
    distance: t("stats.distance"),
    duration: t("stats.duration"),
    avgSpeed: t("stats.avg_speed"),
  })
  target.replaceChildren(
    make("pb-1", heading),
    ...rows.map((row) => {
      const line = make("flex items-baseline justify-between gap-2")
      const label = make("min-w-0", row.label)
      const value = make("shrink-0 tabular-nums opacity-90", row.value)
      line.append?.(label, value)
      return line
    }),
  )
}
