import { DAWARICH_URL, formatFor, provenanceOf } from "./state.js"

export function createExportControls(ctx, deps) {
  const { t, video } = ctx
  const { runs, renderVideo, upload, urls, request, el, fonts } = deps
  let saveController = null

  function showResult(blob) {
    ctx.result = { blob, url: urls.createObjectURL(blob) }
    const player = el("result")
    if (player) {
      player.src = ctx.result.url
      player.classList.remove("hidden")
    }
    ctx.preview?.clearOverlay()
    const save = el("save")
    if (save) save.disabled = false
    ctx.setStatus(t("ready", { size: (blob.size / (1024 * 1024)).toFixed(1) }))
  }

  function options(signal, gen) {
    const s = ctx.settings
    const { width, height } = formatFor(s)
    return {
      style: ctx.style,
      trackGeojson: ctx.track.trackGeojson,
      points: ctx.track.points,
      stats: ctx.stats,
      width,
      height,
      durationSec: s.duration_sec,
      cameraMode: s.camera_mode,
      followZoom: s.follow_zoom,
      accent: s.track_color,
      units: s.units,
      themeBg: ctx.themeTokens?.bg,
      hudScale: s.hud_scale / 100,
      fontUrls: fonts,
      labels: ctx.hudLabels(),
      watermark: s.watermark ? DAWARICH_URL : null,
      visualizationMode: s.visualization_mode,
      fogOpacity: s.fog_opacity / 100,
      fogColor: s.fog_color,
      showMarker: s.show_marker,
      signal,
      onProgress: (done, total) =>
        ctx.current(gen) && ctx.showProgress(done / total, "rendering"),
    }
  }

  async function render() {
    if (!ctx.style || ctx.rendering || ctx.rangeLoading) return
    if (ctx.track.points.length < 2) {
      ctx.setStatus(t("empty_track"))
      return
    }
    const gen = ctx.generation
    ctx.clearResult()
    ctx.setRendering(true)
    try {
      await runs.perform(
        (signal) =>
          renderVideo(options(signal, gen), {
            kit: ctx.kit,
            loadLibrary: async () => ctx.library,
          }),
        ({ blob }) => ctx.current(gen) && showResult(blob),
      )
    } catch (error) {
      if (ctx.current(gen) && error?.name !== "AbortError")
        ctx.setStatus(
          error.code === "unsupported_browser"
            ? t("unsupported_browser")
            : error.message,
        )
    } finally {
      if (!runs.active) ctx.setRendering(false)
    }
  }

  async function save() {
    if (!ctx.result || ctx.rangeLoading || saveController) return
    const gen = ctx.generation
    const controller = new AbortController()
    saveController = controller
    const button = el("save")
    if (button) button.disabled = true
    try {
      await upload({
        blob: ctx.result.blob,
        name: el("name")?.value ?? "",
        settings: {
          ...ctx.settings,
          ...provenanceOf({ fixed: video.fixed, range: ctx.track.range }),
        },
        request,
        signal: controller.signal,
        onProgress: (ratio) =>
          ctx.current(gen) && ctx.showProgress(ratio, "uploading"),
      })
      if (ctx.current(gen)) ctx.showProgress(0, null)
    } catch (error) {
      if (ctx.current(gen) && error?.name !== "AbortError")
        ctx.setStatus(t("save_failed", { error: error.message }))
    } finally {
      if (saveController === controller) saveController = null
      if (ctx.current(gen) && button) button.disabled = !ctx.result
    }
  }

  return { render, save, abortSave: () => saveController?.abort() }
}
