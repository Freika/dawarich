import {
  formatDateTimeRange,
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "./date_range.js"
import { rangeRestorePlan, readProvenance } from "./state.js"

const find = (root, name) => root.querySelector(`[data-video-${name}]`)

export function createRangeControls(ctx) {
  const { root, video, t } = ctx
  const el = (name) => find(root, name)

  function rangeLabel() {
    const { startAt, endAt, timezone } = ctx.track?.range ?? {}
    return formatDateTimeRange(
      startAt,
      endAt,
      ctx.document?.documentElement?.lang || undefined,
      timezone,
    )
  }

  function sync() {
    const editable = !video.fixed
    el("range-controls")?.classList.toggle("hidden", !editable)
    el("range-display")?.classList.toggle("hidden", editable)
    const label = el("range-label")
    if (label) label.textContent = rangeLabel()
    const start = el("start")
    const end = el("end")
    if (!editable || !start || !end) return
    const { startAt, endAt, timezone } = ctx.track?.range ?? {}
    start.value = toLocalDateTimeInput(startAt, timezone)
    end.value = toLocalDateTimeInput(endAt, timezone)
  }

  function setBusy(value) {
    ctx.rangeLoading = value
    for (const name of ["load", "start", "end", "switch"]) {
      const control = el(name)
      if (control) control.disabled = value || ctx.rendering
    }
    el("load-spinner")?.classList.toggle("hidden", !value)
    const save = el("save")
    if (value && save) save.disabled = true
    ctx.syncRender()
  }

  async function navigate(range, gen, { autoName = false } = {}) {
    const name = el("name")
    const previous = el("range-label")?.textContent ?? rangeLabel()
    const nameWasAuto = autoName && name && name.value === previous
    ctx.clearResult()
    ctx.style = null
    setBusy(true)
    try {
      ctx.applyTrack(
        await video.applyDates(range, { signal: ctx.openSignal() }),
        gen,
      )
      if (!ctx.current(gen)) return false
      sync()
      if (nameWasAuto) name.value = rangeLabel()
      await ctx.refreshStyle(gen)
      return ctx.current(gen)
    } finally {
      if (ctx.current(gen)) setBusy(false)
    }
  }

  async function applyDates() {
    if (video.fixed || ctx.rendering || ctx.rangeLoading || !ctx.track) return
    const start = el("start")
    const end = el("end")
    const range = selectableDateTimeRange(
      start?.value,
      end?.value,
      ctx.track.range?.timezone,
    )
    if (!range) {
      end?.setCustomValidity(t("start_before_end"))
      end?.reportValidity?.()
      return
    }
    end?.setCustomValidity("")
    const gen = ctx.bump()
    ctx.setStatus(t("loading_tracks"))
    try {
      await navigate({ startAt: range.start, endAt: range.end }, gen, {
        autoName: true,
      })
      if (ctx.current(gen)) ctx.setStatus("")
    } catch (error) {
      if (ctx.current(gen) && error?.name !== "AbortError")
        ctx.setStatus(t("open_failed", { error: error.message }))
    }
  }

  async function restore(raw) {
    const provenance = readProvenance(raw)
    const plan = rangeRestorePlan(provenance, ctx.track?.range ?? {}, {
      fixed: video.fixed,
    })
    if (plan.action === "none") return true
    if (plan.action === "warn") {
      ctx.setStatus(t("range_mismatch", { range: plan.range }))
      return true
    }
    const gen = ctx.generation
    ctx.setStatus(t("restoring_range"))
    try {
      const done = await navigate(
        { startAt: plan.start_at, endAt: plan.end_at },
        gen,
      )
      if (done) ctx.setStatus("")
      return done
    } catch {
      if (ctx.current(gen))
        ctx.setStatus(t("range_mismatch", { range: plan.range }))
      return false
    }
  }

  return { rangeLabel, sync, setBusy, applyDates, restore }
}
