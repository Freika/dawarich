import { createLifecycle } from "../map/runtime/lifecycle.js"
import { bindVideoControls, syncVideoControls } from "./controls.js"
import { ensureHudFonts } from "./hud_fonts.js"
import { isVideoExportSupported } from "./mp4_encoder.js"
import { createVideoPreview } from "./preview.js"
import { renderRouteVideo } from "./render/engine.js"
import { createRenderRuns } from "./render/operation.js"
import { buildRouteClock } from "./route_clock.js"
import { buildRouteTimeline } from "./route_timeline.js"
import { createVideoSource } from "./source.js"
import { buildVideoStyle, defaultSettings, normalizeSettings } from "./state.js"
import { createExportControls } from "./studio_export.js"
import { createRangeControls } from "./studio_range.js"
import { renderSummary } from "./studio_view.js"
import { uploadRenderedVideo } from "./upload.js"
import { computeTrackStats } from "./video_stats.js"

export const interpolate = (text, values = {}) =>
  (text ?? "").replace(/%\{(\w+)\}/g, (match, name) => values[name] ?? match)

export function mountVideoStudio({ root, source, request, deps = {} }) {
  const win = deps.window ?? globalThis.window
  const urls = deps.URL ?? globalThis.URL
  const loadLibrary =
    deps.loadLibrary ?? (() => import("/maplibre/6.4.1/maplibre-gl.mjs"))
  const loadKit = deps.loadKit ?? (() => import("./dependencies.js"))
  const renderVideo = deps.renderVideo ?? renderRouteVideo
  const upload = deps.upload ?? uploadRenderedVideo
  const ensureFonts = deps.ensureFonts ?? ensureHudFonts
  const supported = deps.isSupported ?? (() => isVideoExportSupported())
  const config = JSON.parse(root.dataset.videoConfig ?? "{}")
  const strings = config.strings ?? {}
  const t = (key, values) => interpolate(strings[key], values)
  const el = (name) => root.querySelector(`[data-video-${name}]`)
  const owned = createLifecycle()
  const runs = createRenderRuns()
  const video = createVideoSource(source)
  let openController = null
  let opened = false
  let styleOperation = 0

  const ctx = {
    root,
    video,
    t,
    document: deps.document ?? globalThis.document,
    generation: 0,
    rangeLoading: false,
    rendering: false,
    settings: defaultSettings(),
    track: null,
    style: null,
    current: (gen) => !owned.destroyed && opened && gen === ctx.generation,
    bump: () => ++ctx.generation,
    openSignal: () => openController?.signal,
    setStatus(text) {
      const status = el("status")
      if (status) status.textContent = text
    },
    syncRender() {
      const button = el("render")
      if (button)
        button.disabled = Boolean(
          ctx.rendering || ctx.rangeLoading || !ctx.style || !supported(),
        )
    },
    applyTrack(loaded, gen) {
      if (!ctx.current(gen)) return
      ctx.track = loaded
      ctx.stats = computeTrackStats(loaded.points)
      ctx.clock = buildRouteClock(loaded.points)
      ctx.timeline = buildRouteTimeline(loaded.trackGeojson, { smooth: true })
    },
    async refreshStyle(gen) {
      const operation = ++styleOperation
      const settings = { ...ctx.settings }
      ctx.style = null
      ctx.syncRender()
      let tokens
      try {
        tokens = await ctx.kit.loadThemeTokens(settings.theme, {
          signal: openController?.signal,
        })
      } catch (error) {
        if (ctx.current(gen) && operation === styleOperation) throw error
        return
      }
      if (!ctx.current(gen) || operation !== styleOperation) return
      ctx.themeTokens = tokens
      ctx.style = buildVideoStyle(
        {
          tokens,
          trackGeojson: ctx.track.trackGeojson,
          settings,
        },
        ctx.kit,
      )
      ctx.preview ??= createVideoPreview({
        elements: {
          stage: el("stage"),
          frame: el("frame"),
          preview: el("preview"),
          overlay: el("overlay"),
        },
        library: ctx.library,
        window: win,
      })
      ctx.preview.show({
        style: ctx.style,
        settings,
        bounds: ctx.kit.trackBounds(ctx.track.trackGeojson),
        stats: ctx.stats,
        clock: ctx.clock,
        timeline: ctx.timeline,
        families: ctx.families,
        labels: ctx.hudLabels(),
        themeBg: tokens?.bg,
      })
      renderSummary(root, ctx)
      ctx.syncRender()
    },
    clearResult() {
      if (ctx.result) urls.revokeObjectURL(ctx.result.url)
      ctx.result = null
      const player = el("result")
      if (player) {
        player.removeAttribute("src")
        player.classList.add("hidden")
      }
      const save = el("save")
      if (save) save.disabled = true
      ctx.showProgress(0, null)
      ctx.preview?.drawOverlay()
    },
    hudLabels: () => ({
      day: t("hud.day"),
      distance: t("hud.distance"),
      ofTotal: t("hud.of_total"),
      tagline: t("hud.tagline"),
      travelledOver: (days) => t("hud.travelled_over", { days }),
    }),
    showProgress(ratio, phase) {
      const value = Math.max(0, Math.min(1, ratio || 0))
      const bar = el("progress")
      if (bar) {
        bar.style.transform = `scaleX(${value})`
        bar.setAttribute("aria-valuenow", String(Math.round(value * 100)))
      }
      ctx.setStatus(phase ? t(phase, { percent: Math.round(value * 100) }) : "")
    },
    setRendering(value) {
      ctx.rendering = value
      for (const name of ["load", "start", "end", "switch"]) {
        const control = el(name)
        if (control) control.disabled = value || ctx.rangeLoading
      }
      el("cancel")?.classList.toggle("hidden", !value)
      ctx.syncRender()
    },
  }
  const range = createRangeControls(ctx)
  const exporter = createExportControls(ctx, {
    runs,
    renderVideo,
    upload,
    urls,
    request,
    el,
    fonts: config.fonts,
  })

  function syncSupport() {
    ctx.syncRender()
    if (!supported()) ctx.setStatus(t("unsupported_browser"))
  }

  async function open(recipe) {
    if (!opened) {
      opened = true
      const gen = ctx.bump()
      openController = new AbortController()
      el("dialog")?.showModal?.()
      range.setBusy(true)
      el("close")?.focus?.()
      try {
        const [kit, library] = await Promise.all([loadKit(), loadLibrary()])
        if (!ctx.current(gen)) return
        Object.assign(ctx, { kit, library })
        ctx.applyTrack(await video.load({ signal: openController.signal }), gen)
        if (!ctx.current(gen)) return
        range.sync()
        const name = el("name")
        if (name && !name.value)
          name.value = ctx.track.title || range.rangeLabel()
        ctx.families = await ensureFonts(config.fonts, {
          signal: openController.signal,
        })
        if (!ctx.current(gen)) return
        syncVideoControls(root, ctx.settings)
        await ctx.refreshStyle(gen)
        if (ctx.current(gen)) syncSupport()
      } catch (error) {
        if (ctx.current(gen) && error?.name !== "AbortError")
          ctx.setStatus(t("open_failed", { error: error.message }))
      } finally {
        if (ctx.current(gen)) range.setBusy(false)
      }
    }
    if (recipe && ctx.track) await restore(recipe)
  }

  async function restore(raw) {
    if (ctx.rendering || ctx.rangeLoading) return
    let parsed = null
    try {
      parsed = typeof raw === "string" ? JSON.parse(raw) : raw
    } catch {}
    ctx.settings = normalizeSettings(parsed)
    syncVideoControls(root, ctx.settings)
    const gen = ctx.generation
    if ((await range.restore(parsed)) && ctx.current(gen)) {
      ctx.clearResult()
      await ctx.refreshStyle(gen)
    }
  }

  async function change(patch) {
    ctx.settings = { ...ctx.settings, ...patch }
    syncVideoControls(root, ctx.settings, ctx.document?.activeElement)
    if (!ctx.track || ctx.rangeLoading) return
    ctx.clearResult()
    const gen = ctx.generation
    const operation = styleOperation + 1
    try {
      await ctx.refreshStyle(gen)
    } catch (error) {
      if (
        ctx.current(gen) &&
        operation === styleOperation &&
        error?.name !== "AbortError"
      )
        ctx.setStatus(error.message)
    }
  }

  function close() {
    if (!opened) return
    ctx.bump()
    opened = false
    openController?.abort()
    runs.cancel()
    exporter.abortSave()
    ctx.preview?.destroy()
    ctx.preview = null
    ctx.style = null
    ctx.clearResult()
    range.setBusy(false)
    ctx.setRendering(false)
    const dialog = el("dialog")
    if (dialog?.open) dialog.close()
  }

  function switchStudio() {
    if (ctx.rendering || ctx.rangeLoading) return
    close()
    root.dispatchEvent(
      new CustomEvent("dawarich:studio-switch", {
        bubbles: true,
        detail: { studio: "poster", source },
      }),
    )
  }

  const studio = {
    open,
    close,
    render: exporter.render,
    cancel: () => runs.cancel(),
    save: exporter.save,
    change,
    applyDates: () => range.applyDates(),
    switchStudio,
    resize: () => ctx.preview?.resize(),
    get settings() {
      return ctx.settings
    },
    destroy() {
      close()
      owned.destroy()
      video.destroy()
    },
  }
  owned.own(bindVideoControls({ root, studio, window: win }))
  syncVideoControls(root, ctx.settings)
  return studio
}
