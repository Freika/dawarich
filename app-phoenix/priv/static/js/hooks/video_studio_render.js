import { translate } from "i18n"
import { isVideoExportSupported } from "video_studio/mp4_encoder"
import { formatFor, DAWARICH_URL } from "video_studio/studio_state"

export const rendering = {
  async render() {
    if (!this.style || this.rendering || this.rangeLoading) return
    if (this.points.length < 2) {
      this.statusTarget.textContent = translate("video.empty_track")
      return
    }
    this.rendering = true
    this.clearResult()
    const operation = this.operationVersion
    const controller = new AbortController()
    this.abortController = controller
    this.setBusy(true)

    try {
      const { renderRouteVideo } = await import("video_studio/video_renderer")
      const { width, height } = formatFor(this.settings)
      const { blob } = await renderRouteVideo({
        style: this.style,
        trackGeojson: this.trackGeojson,
        points: this.points,
        stats: this.stats,
        width,
        height,
        durationSec: this.settings.duration_sec,
        cameraMode: this.settings.camera_mode,
        followZoom: this.settings.follow_zoom,
        accent: this.settings.track_color,
        units: this.settings.units,
        themeBg: this.themeTokens?.bg,
        hudScale: this.settings.hud_scale / 100,
        fontUrls: this.fontsValue,
        labels: this.hudLabels(),
        watermark: this.settings.watermark ? DAWARICH_URL : null,
        visualizationMode: this.settings.visualization_mode,
        fogOpacity: this.settings.fog_opacity / 100,
        fogColor: this.settings.fog_color,
        showMarker: this.settings.show_marker,
        onProgress: (done, total) =>
          this.operationIsCurrent(operation) &&
          this.showProgress(done / total, "rendering"),
        signal: controller.signal,
      })
      if (this.operationIsCurrent(operation) && !controller.signal.aborted)
        this.showResult(blob)
    } catch (error) {
      if (error.message !== "Render cancelled") {
        if (this.operationIsCurrent(operation))
          this.statusTarget.textContent = error.message
      }
    } finally {
      this.rendering = false
      if (this.abortController === controller) this.abortController = null
      if (this.operationIsCurrent(operation)) this.setBusy(false)
    }
  },
  cancel() {
    this.abortController?.abort()
  },
  showProgress(ratio, phase) {
    const progress = Math.max(0, Math.min(1, ratio || 0))
    this.progressBarTarget.style.transform = `scaleX(${progress})`
    this.progressBarTarget.setAttribute(
      "aria-valuenow",
      String(Math.round(progress * 100)),
    )
    this.statusTarget.textContent = phase
      ? translate(`video.${phase}`, { percent: Math.round(progress * 100) })
      : ""
  },
  hideHudPreview() {
    if (!this.hasOverlayTarget) return
    const ctx = this.overlayTarget.getContext("2d")
    ctx.clearRect(0, 0, this.overlayTarget.width, this.overlayTarget.height)
  },
  showResult(blob) {
    this.blob = blob
    this.resultUrl = URL.createObjectURL(blob)
    this.resultTarget.src = this.resultUrl
    this.resultTarget.classList.remove("hidden")
    this.hideHudPreview()
    this.saveButtonTarget.disabled = false
    this.statusTarget.textContent = translate("video.ready", {
      size: (blob.size / (1024 * 1024)).toFixed(1),
    })
  },
  clearResult() {
    if (this.resultUrl) URL.revokeObjectURL(this.resultUrl)
    this.resultUrl = null
    this.blob = null
    this.resultTarget.removeAttribute("src")
    this.resultTarget.classList.add("hidden")
    this.drawHudPreview()
    this.saveButtonTarget.disabled = true
    this.showProgress(0, null)
  },
  setBusy(busy) {
    if (this.hasLoadButtonTarget) this.loadButtonTarget.disabled = busy
    if (this.hasDateStartTarget) this.dateStartTarget.disabled = busy
    if (this.hasDateEndTarget) this.dateEndTarget.disabled = busy
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.disabled = busy
    this.cancelButtonTarget.classList.toggle("hidden", !busy)
    this.syncRenderAvailability()
  },
  syncRenderAvailability() {
    if (!this.hasRenderButtonTarget) return
    this.renderButtonTarget.disabled = Boolean(
      this.rendering ||
      this.rangeLoading ||
      !this.style ||
      !isVideoExportSupported(),
    )
  },
  syncSupport() {
    this.syncRenderAvailability()
    if (!isVideoExportSupported()) {
      this.statusTarget.textContent = translate("video.unsupported_browser")
    }
  },
  teardown() {
    this.previewMap?.remove()
    this.previewMap = null
    this.clearResult()
  },
}
