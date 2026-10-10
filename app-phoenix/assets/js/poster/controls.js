import { createLifecycle } from "../map/runtime/lifecycle.js"
import { presetRange, toLocalDateTimeInput } from "./dates.js"
import { bindLayoutControls } from "./layout_controls.js"
import { bindTextControls } from "./text_controls.js"

export function bindPosterControls({
  root,
  studio,
  poster,
  strings = {},
  maxDimensionPx,
  ensureFont,
  now = () => new Date(),
}) {
  const owned = createLifecycle()
  const find = (name) => root.querySelector(`[data-poster-${name}]`)
  const on = (element, type, handler) => {
    if (!element) return
    element.addEventListener(type, handler)
    owned.own(() => element.removeEventListener(type, handler))
  }
  const sync = (element, key, value) => {
    if (element && element[key] !== value) element[key] = value
  }
  const themeName = () =>
    find("theme-label")?.textContent || studio.state.themeKey || ""
  const context = {
    root,
    find,
    on,
    sync,
    studio,
    maxDimensionPx,
    themeName,
    ensureFont,
  }
  const layout = bindLayoutControls(context)
  const text = bindTextControls(context)
  let seededData = null

  const timeZone = () => studio.state.data?.timeZone

  function seedDates() {
    const data = studio.state.data
    if (!data || data === seededData || !data.range?.startAt) return
    seededData = data
    const start = find("date-start")
    const end = find("date-end")
    if (start)
      start.value = toLocalDateTimeInput(data.range.startAt, timeZone())
    if (end) end.value = toLocalDateTimeInput(data.range.endAt, timeZone())
  }

  function setBusy(busy) {
    const load = find("load")
    if (load) load.disabled = busy
    find("load-spinner")?.classList.toggle("hidden", !busy)
    const label = find("load-label")
    if (label) label.textContent = (busy ? strings.loading : strings.load) ?? ""
    const toggle = find("switch-video")
    if (toggle) toggle.disabled = busy
    const status = find("status")
    if (status) status.textContent = busy ? (strings.loading_tracks ?? "") : ""
  }

  async function applyDates() {
    if (!poster || poster.fixed) return
    const start = find("date-start")?.value
    const end = find("date-end")?.value
    if (!start || !end) return
    const current = studio.state.data?.range ?? {}
    let failed = false
    setBusy(true)
    try {
      await studio.applyRange({
        startAt: start,
        endAt: end,
        importId: current.importId ?? null,
        timezone: current.timezone,
      })
    } catch (error) {
      failed = error?.name !== "AbortError"
    } finally {
      setBusy(false)
      if (failed) {
        seededData = null
        const status = find("status")
        if (status) status.textContent = strings.range_failed ?? ""
      }
      refresh()
    }
  }

  on(find("load"), "click", () => applyDates())
  for (const preset of root.querySelectorAll("[data-poster-range]")) {
    on(preset, "click", () => {
      const range = presetRange(preset.dataset.posterRange, now(), timeZone())
      const start = find("date-start")
      const end = find("date-end")
      if (start) start.value = range.start
      if (end) end.value = range.end
      applyDates()
    })
  }

  function refresh() {
    seedDates()
    layout.refresh()
    text.refresh()
  }

  refresh()
  return Object.assign(() => owned.destroy(), { refresh })
}
