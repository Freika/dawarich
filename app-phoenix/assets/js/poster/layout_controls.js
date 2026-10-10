import { layoutById, resolveLayoutGeometry } from "./data/layouts.js"

export function layoutSummary(
  state,
  { layoutLabel, themeName, maxDimensionPx },
) {
  const layout = layoutById(state.layoutId)
  const geometry = resolveLayoutGeometry(layout, state.dpi, { maxDimensionPx })
  const dpi = layout.kind === "paper" ? ` @ ${geometry.effectiveDpi} dpi` : ""
  return [
    `${layoutLabel} — ${layout.dimensionsLabel}`,
    `Theme: ${themeName || "—"}`,
    `Export: ${geometry.width} × ${geometry.height}px${dpi}`,
  ].join(" · ")
}

export function bindLayoutControls({
  find,
  on,
  studio,
  maxDimensionPx,
  themeName,
}) {
  const select = find("layout")
  const format = find("format")
  const dpi = find("dpi")

  function refresh() {
    const layout = layoutById(studio.state.layoutId)
    const isPaper = layout.kind === "paper"
    const dims = find("layout-dims")
    if (dims) dims.textContent = layout.dimensionsLabel
    find("dpi-field")?.classList.toggle("invisible", !isPaper)
    const pdf = format?.querySelector('option[value="pdf"]')
    if (pdf) pdf.disabled = !isPaper
    if (!isPaper && format?.value === "pdf") {
      format.value = "png"
      studio.update({ format: "png" })
    }
    const summary = find("summary")
    if (summary)
      summary.textContent = layoutSummary(studio.state, {
        layoutLabel: select?.selectedOptions?.[0]?.textContent?.trim() ?? "",
        themeName: themeName(),
        maxDimensionPx,
      })
  }

  on(select, "change", () => {
    studio.update({ layoutId: select.value })
    refresh()
  })
  on(format, "change", () => {
    studio.update({ format: format.value })
    refresh()
  })
  on(dpi, "change", () => {
    studio.update({ dpi: Number.parseInt(dpi.value, 10) })
    refresh()
  })
  return { refresh }
}
