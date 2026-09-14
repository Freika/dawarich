import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import maplibregl from "maplibre-gl"
import { MapPageProvider } from "poster_studio/data/providers"
import { loadThemeTokens } from "poster_studio/data/theme_loader"
import { trackBounds } from "poster_studio/ui/preview"
import {
  formatDateTimeRange,
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "video_studio/date_range"
import { ensureHudFonts } from "video_studio/hud_fonts"
import { drawHud } from "video_studio/hud_overlay"
import { loadTrack } from "video_studio/load_track"
import { isVideoExportSupported } from "video_studio/mp4_encoder"
import { toVideoPoints } from "video_studio/points"
import { buildRouteClock } from "video_studio/route_clock"
import { saveVideo } from "video_studio/save_video"
import {
  buildVideoStyle,
  DAWARICH_URL,
  defaultSettings,
  formatFor,
  normalizeSettings,
  previewFitPadding,
  provenanceOf,
  rangeRestorePlan,
  readProvenance,
} from "video_studio/studio_state"
import { buildStatRows, computeTrackStats } from "video_studio/video_stats"
import Flash from "./flash_controller"

// The route video studio: a full-screen overlay that previews the map, renders
// an MP4 in the browser via WebCodecs, and hands the finished blob to the
// backend. Rendering lives in video_studio/*; this controller owns the DOM.
const HUD_PREVIEW_FRACTION = 0.62

export default class extends Controller {
  static targets = [
    "stage",
    "frame",
    "preview",
    "overlay",
    "result",
    "status",
    "progressBar",
    "renderButton",
    "saveButton",
    "cancelButton",
    "nameInput",
    "themeSwatch",
    "themeLabel",
    "durationLabel",
    "trackWidthLabel",
    "hudScaleLabel",
    "formatDims",
    "dateStart",
    "dateEnd",
    "rangeControls",
    "rangeDisplay",
    "loadButton",
    "loadSpinner",
    "switchButton",
    "rangeLabel",
    "summary",
  ]

  static values = {
    fonts: Object,
    uploadUrl: String,
    createUrl: String,
  }

  connect() {
    // The map page wraps content in a stacking context that would trap the
    // overlay under the navbar — portal to <body>. Moving the node re-runs
    // connect, hence the guard.
    if (this.element.parentElement !== document.body) {
      document.body.appendChild(this.element)
      return
    }
    this.operationVersion ??= 0
    this.settings = defaultSettings()
    this.onOpen = (event) => this.open(event.detail?.provider)
    document.addEventListener("video-studio:open", this.onOpen)
    this.onResize = () => {
      this.resizeFrame()
      this.previewMap?.resize()
    }
    window.addEventListener("resize", this.onResize)
    this.syncControls()
  }

  disconnect() {
    this.invalidateOperation()
    document.removeEventListener("video-studio:open", this.onOpen)
    window.removeEventListener("resize", this.onResize)
    this.teardown()
  }

  async open(provider = null) {
    if (!this.element.classList.contains("hidden")) return
    const operation = this.startOperation()
    this.provider =
      provider ?? new MapPageProvider({ application: this.application })
    this.element.classList.remove("hidden")
    this.syncDateTimeControls()
    this.setRangeBusy(true)

    try {
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return
      if (!this.nameInputTarget.value) {
        this.nameInputTarget.value =
          this.provider.defaultTitle() || this.dateRangeLabel()
      }
      const families = await ensureHudFonts(this.fontsValue)
      if (!this.operationIsCurrent(operation)) return
      this.families = families
      await this.refreshStyle(operation)
      if (!this.operationIsCurrent(operation)) return
      this.renderStats()
      this.syncSupport()
    } catch (error) {
      if (this.operationIsCurrent(operation)) {
        Flash.show(
          "error",
          translate("video.open_failed", { error: error.message }),
        )
      }
    } finally {
      if (this.operationIsCurrent(operation)) this.setRangeBusy(false)
    }
  }

  close() {
    this.invalidateOperation()
    this.cancel()
    this.teardown()
    this.setRangeBusy(false)
    this.element.classList.add("hidden")
  }

  // The two studios are alternate views of the same track and date range, so
  // switching carries the provider across — a trip-locked studio stays locked
  // to that trip rather than falling back to the map page.
  switchToPoster() {
    if (this.rendering || this.rangeLoading) return
    const provider = this.provider
    this.close()
    document.dispatchEvent(
      new CustomEvent("poster-studio:open", { detail: { provider } }),
    )
  }

  // ===== settings =====

  selectTheme(event) {
    this.settings.theme = event.currentTarget.dataset.themeKey
    this.settingsChanged()
  }

  resetTrackColor() {
    this.settings.track_color = defaultSettings().track_color
    this.settingsChanged()
  }

  updateSetting(event) {
    const { setting } = event.currentTarget.dataset
    const input = event.currentTarget
    const value =
      input.type === "checkbox"
        ? input.checked
        : input.type === "range" || input.type === "number"
          ? Number(input.value)
          : input.value

    this.settings[setting] = value
    this.settingsChanged()
  }

  // Re-seeds the studio from an expired video's stored recipe (option C: the
  // row outlives the blob, so the settings are enough to make it again).
  async restoreSettings(event) {
    if (this.rendering || this.rangeLoading) return
    const operation = this.startOperation()
    let raw = null
    try {
      raw = JSON.parse(event.currentTarget.dataset.settings)
      this.settings = normalizeSettings(raw)
    } catch {
      this.settings = defaultSettings()
    }
    this.syncControls()
    const restored = await this.restoreRange(readProvenance(raw), operation)
    if (!restored || !this.operationIsCurrent(operation)) return
    await this.settingsChanged(operation)
    if (!this.operationIsCurrent(operation)) return
    this.syncDateTimeControls()
  }

  // Styling alone is not the recipe: a video made from a different date range
  // has to bring that range back, or "re-render" quietly rebuilds whatever the
  // page is showing now under the old video's looks.
  async restoreRange(provenance, operation = this.startOperation()) {
    const plan = rangeRestorePlan(
      provenance,
      this.provider.dateRange(),
      this.provider,
    )
    if (plan.action === "none") return true

    const warn = () => {
      this.statusTarget.textContent = translate("video.range_mismatch", {
        range: plan.range,
      })
    }
    if (plan.action === "warn") {
      warn()
      return true
    }

    this.clearResult()
    this.style = null
    this.setRangeBusy(true)
    this.statusTarget.textContent = translate("video.restoring_range")
    try {
      await this.provider.applyDates(plan.start_at, plan.end_at)
      if (!this.operationIsCurrent(operation)) return false
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return false
      this.statusTarget.textContent = ""
      return true
    } catch {
      // A reload that never lands leaves the old track in place, which is the
      // route the user did not ask for — say so rather than render it.
      if (this.operationIsCurrent(operation)) warn()
      return false
    } finally {
      if (this.operationIsCurrent(operation)) this.setRangeBusy(false)
    }
  }

  // Date changes stay inside the open studio. Map-backed providers update the
  // main map in place; trip-backed providers keep their fixed range display.
  syncDateTimeControls() {
    const editable = Boolean(this.provider?.supportsDateNavigation)
    if (this.hasRangeControlsTarget) {
      this.rangeControlsTarget.classList.toggle("hidden", !editable)
    }
    if (this.hasRangeDisplayTarget) {
      this.rangeDisplayTarget.classList.toggle("hidden", editable)
    }
    if (!editable || !this.hasDateStartTarget || !this.hasDateEndTarget) return

    const { startAt, endAt } = this.provider.dateRange()
    const timeZone = this.provider.timeZone?.()
    this.dateStartTarget.value = toLocalDateTimeInput(startAt, timeZone)
    this.dateEndTarget.value = toLocalDateTimeInput(endAt, timeZone)
  }

  async applyDateTimeRange() {
    if (
      !this.provider?.supportsDateNavigation ||
      this.rendering ||
      this.rangeLoading
    )
      return
    const range = selectableDateTimeRange(
      this.dateStartTarget.value,
      this.dateEndTarget.value,
      this.provider.timeZone?.(),
    )
    if (!range) {
      this.dateEndTarget.setCustomValidity(
        translate("datetime.start_before_end"),
      )
      this.dateEndTarget.reportValidity()
      return
    }

    this.dateEndTarget.setCustomValidity("")
    // The provider mutates its range before a failed map reload rejects. The
    // visible range label only changes after a successful track reload, so it
    // remains the reliable reference for whether this name is automatic.
    const currentRangeLabel = this.hasRangeLabelTarget
      ? this.rangeLabelTarget.textContent
      : this.dateRangeLabel()
    const nameWasAuto = this.nameInputTarget.value === currentRangeLabel
    const operation = this.startOperation()
    this.clearResult()
    this.style = null
    this.setRangeBusy(true)
    this.statusTarget.textContent = translate("poster.loading_tracks")
    try {
      await this.provider.applyDates(range.start, range.end)
      if (!this.operationIsCurrent(operation)) return
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return
      this.syncDateTimeControls()
      if (nameWasAuto) this.nameInputTarget.value = this.dateRangeLabel()
      await this.refreshStyle(operation)
      if (!this.operationIsCurrent(operation)) return
      this.renderStats()
    } catch (error) {
      if (this.operationIsCurrent(operation)) {
        Flash.show(
          "error",
          translate("video.open_failed", { error: error.message }),
        )
      }
    } finally {
      if (this.operationIsCurrent(operation)) {
        this.statusTarget.textContent = ""
        this.setRangeBusy(false)
      }
    }
  }

  setRangeBusy(value) {
    this.rangeLoading = value
    if (this.hasLoadButtonTarget) this.loadButtonTarget.disabled = value
    if (this.hasLoadSpinnerTarget) {
      this.loadSpinnerTarget.classList.toggle("hidden", !value)
    }
    if (this.hasDateStartTarget) this.dateStartTarget.disabled = value
    if (this.hasDateEndTarget) this.dateEndTarget.disabled = value
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.disabled = value
    if (value && this.hasSaveButtonTarget) this.saveButtonTarget.disabled = true
    this.syncRenderAvailability()
  }

  async reloadTrack(operation = null) {
    const { trackGeojson, points } = await loadTrack(this.provider)
    if (operation !== null && !this.operationIsCurrent(operation)) return
    this.trackGeojson = trackGeojson
    this.points = toVideoPoints(points)
    this.stats = computeTrackStats(this.points)
    this.clock = buildRouteClock(this.points)
    if (this.hasRangeLabelTarget) {
      this.rangeLabelTarget.textContent = this.dateRangeLabel()
    }
  }

  async settingsChanged(operation = null) {
    this.syncControls()
    this.clearResult()
    await this.refreshStyle(operation)
    if (operation !== null && !this.operationIsCurrent(operation)) return
    this.renderStats()
    this.syncRenderAvailability()
  }

  syncControls() {
    if (this.hasDurationLabelTarget) {
      this.durationLabelTarget.textContent = `${this.settings.duration_sec}s`
    }
    if (this.hasHudScaleLabelTarget) {
      this.hudScaleLabelTarget.textContent = `${Math.round(this.settings.hud_scale)}%`
    }
    if (this.hasTrackWidthLabelTarget) {
      this.trackWidthLabelTarget.textContent = `${Math.round(this.settings.track_width)}%`
    }
    // Selects belong here too — leaving them out silently drops any restored
    // value that is not the first option.
    for (const input of this.element.querySelectorAll(
      "input[data-setting], select[data-setting]",
    )) {
      const value = this.settings[input.dataset.setting]
      if (input.type === "checkbox") input.checked = Boolean(value)
      else if (document.activeElement !== input) input.value = value
    }
    for (const swatch of this.themeSwatchTargets) {
      const active = swatch.dataset.themeKey === this.settings.theme
      swatch.setAttribute("aria-pressed", String(active))
      swatch.classList.toggle("ring-2", active)
      swatch.classList.toggle("ring-offset-1", active)
      if (active && this.hasThemeLabelTarget) {
        this.themeLabelTarget.textContent = swatch.dataset.themeName
      }
    }
    if (this.hasFormatDimsTarget) {
      const { width, height } = formatFor(this.settings)
      this.formatDimsTarget.textContent = `${width} × ${height} · ${this.settings.duration_sec}s · 30 fps`
    }
  }

  // ===== preview =====

  async refreshStyle(operation = null) {
    const tokens = await loadThemeTokens(this.settings.theme)
    if (operation !== null && !this.operationIsCurrent(operation)) return
    this.themeTokens = tokens
    this.style = buildVideoStyle({
      tokens,
      trackGeojson: this.trackGeojson,
      settings: this.settings,
    })
    this.drawPreview()
  }

  // Sizes the frame to the largest box of the chosen aspect ratio that fits
  // the stage. Doing it here rather than in CSS keeps the frame exact at every
  // format — an aspect-ratio box with a definite height overflows the stage
  // horizontally the moment the format goes wide.
  resizeFrame() {
    if (!this.hasStageTarget || !this.hasFrameTarget) return
    const { width, height } = formatFor(this.settings)
    const stage = this.stageTarget.getBoundingClientRect()
    const padding = 48
    const available = {
      width: Math.max(0, stage.width - padding),
      height: Math.max(0, stage.height - padding),
    }
    const scale = Math.min(available.width / width, available.height / height)
    this.frameTarget.style.width = `${Math.round(width * scale)}px`
    this.frameTarget.style.height = `${Math.round(height * scale)}px`
    this.drawHudPreview()
  }

  // Paints the real HUD over the preview at preview resolution. Every size in
  // the overlay derives from the frame's short edge, so drawing it small is
  // proportionally identical to the render — what you see here is what gets
  // burned in.
  drawHudPreview() {
    if (!this.hasOverlayTarget || !this.stats) return
    const canvas = this.overlayTarget
    const box = this.frameTarget.getBoundingClientRect()
    if (!box.width || !box.height) return

    const ratio = Math.min(window.devicePixelRatio || 1, 2)
    canvas.width = Math.round(box.width * ratio)
    canvas.height = Math.round(box.height * ratio)
    const ctx = canvas.getContext("2d")
    ctx.clearRect(0, 0, canvas.width, canvas.height)

    drawHud(ctx, {
      width: canvas.width,
      height: canvas.height,
      // A representative moment mid-draw: far enough in that the readouts
      // carry real values rather than zeroes.
      fraction: HUD_PREVIEW_FRACTION,
      outroProgress: 0,
      distanceM: (this.stats?.distanceM ?? 0) * HUD_PREVIEW_FRACTION,
      stats: this.stats,
      units: this.settings.units,
      accent: this.settings.track_color,
      clock: this.clock,
      families: this.families,
      labels: this.hudLabels(),
      watermark: this.settings.watermark ? DAWARICH_URL : null,
      themeBg: this.themeTokens?.bg,
      hudScale: this.settings.hud_scale / 100,
    })
  }

  drawPreview() {
    if (!this.style) return
    this.resizeFrame()

    const bounds =
      trackBounds(this.trackGeojson) ?? this.provider.fallbackBounds()

    if (this.previewMap) {
      this.previewMap.setStyle(this.style)
      this.previewMap.resize()
      // A new format changes the viewport's shape, and MapLibre keeps the old
      // camera through setStyle/resize — without re-fitting, the preview shows
      // a framing the render will not reproduce.
      this.fitPreview(bounds)
      return
    }

    this.previewMap = new maplibregl.Map({
      container: this.previewTarget,
      style: this.style,
      ...(bounds
        ? { bounds, fitBoundsOptions: this.fitOptions() }
        : { center: [0, 0], zoom: 1 }),
      interactive: false,
      attributionControl: false,
    })
  }

  // Padding is scaled to the preview's size so it covers the same fraction of
  // the frame the renderer's does; a fixed 40px would zoom the preview out
  // more than the video, since the preview is smaller.
  fitOptions() {
    return {
      padding: previewFitPadding(
        this.settings,
        this.frameTarget.getBoundingClientRect().width,
      ),
      animate: false,
    }
  }

  fitPreview(bounds) {
    if (!bounds || !this.previewMap) return
    this.previewMap.fitBounds(bounds, this.fitOptions())
  }

  // Mirrors the poster studio's summary block: plain label/value lines under
  // the controls rather than a separate readout component.
  renderStats() {
    if (!this.hasSummaryTarget) return
    const rows = buildStatRows(this.stats, this.settings.units, {
      distance: translate("video.stats.distance"),
      duration: translate("video.stats.duration"),
      avgSpeed: translate("video.stats.avg_speed"),
    })

    // Leading line mirrors the poster studio's summary: what this render will
    // produce, before the numbers describing what goes into it.
    const { width, height } = formatFor(this.settings)
    const descriptor = document.createElement("div")
    descriptor.className = "pb-1"
    descriptor.textContent = translate("video.summary", {
      format: this.formatLabel(),
      width,
      height,
      theme: this.themeTokens?.name ?? "",
      seconds: this.settings.duration_sec,
    })

    this.summaryTarget.replaceChildren(
      descriptor,
      ...rows.map((row) => {
        const line = document.createElement("div")
        line.className = "flex items-baseline justify-between gap-2"
        const label = document.createElement("span")
        label.className = "min-w-0"
        label.textContent = row.label
        const value = document.createElement("span")
        value.className = "shrink-0 tabular-nums opacity-90"
        value.textContent = row.value
        line.append(label, value)
        return line
      }),
    )
  }

  // ===== render =====

  async render() {
    if (!this.style || this.rendering || this.rangeLoading) return
    if (this.points.length < 2) {
      this.statusTarget.textContent = translate("video.empty_track")
      return
    }
    this.rendering = true
    this.clearResult()
    this.abortController = new AbortController()
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
        onProgress: (done, total) =>
          this.showProgress(done / total, "rendering"),
        signal: this.abortController.signal,
      })
      this.showResult(blob)
    } catch (error) {
      if (error.message !== "Render cancelled") {
        this.statusTarget.textContent = error.message
      }
    } finally {
      this.rendering = false
      this.abortController = null
      this.setBusy(false)
    }
  }

  cancel() {
    this.abortController?.abort()
  }

  async save() {
    if (!this.blob || this.rangeLoading) return
    this.saveButtonTarget.disabled = true

    try {
      const stream = await saveVideo({
        blob: this.blob,
        name: this.nameInputTarget.value,
        settings: { ...this.settings, ...provenanceOf(this.provider) },
        uploadUrl: this.uploadUrlValue,
        createUrl: this.createUrlValue,
        onProgress: (ratio) => this.showProgress(ratio, "uploading"),
      })
      Turbo.renderStreamMessage(stream)
      this.showProgress(0, null)
    } catch (error) {
      Flash.show(
        "error",
        translate("video.save_failed", { error: error.message }),
      )
    } finally {
      this.saveButtonTarget.disabled = false
    }
  }

  // ===== helpers =====

  startOperation() {
    this.operationVersion = (this.operationVersion || 0) + 1
    return this.operationVersion
  }

  invalidateOperation() {
    this.operationVersion = (this.operationVersion || 0) + 1
  }

  operationIsCurrent(operation) {
    return operation === this.operationVersion
  }

  hudLabels() {
    return {
      day: translate("video.hud.day"),
      distance: translate("video.hud.distance"),
      ofTotal: translate("video.hud.of_total"),
      tagline: translate("video.hud.tagline"),
      travelledOver: (days) => translate("video.hud.travelled_over", { days }),
    }
  }

  formatLabel() {
    const select = this.element.querySelector('select[data-setting="format"]')
    return (
      select?.selectedOptions?.[0]?.textContent?.trim() ?? this.settings.format
    )
  }

  dateRangeLabel() {
    const { startAt, endAt } = this.provider.dateRange()
    return formatDateTimeRange(
      startAt,
      endAt,
      document.documentElement.lang || undefined,
      this.provider.timeZone?.(),
    )
  }

  showProgress(ratio, phase) {
    this.progressBarTarget.style.transform = `scaleX(${ratio || 0})`
    this.statusTarget.textContent = phase
      ? translate(`video.${phase}`, { percent: Math.round(ratio * 100) })
      : ""
  }

  hideHudPreview() {
    if (!this.hasOverlayTarget) return
    const ctx = this.overlayTarget.getContext("2d")
    ctx.clearRect(0, 0, this.overlayTarget.width, this.overlayTarget.height)
  }

  showResult(blob) {
    this.blob = blob
    this.resultUrl = URL.createObjectURL(blob)
    this.resultTarget.src = this.resultUrl
    this.resultTarget.classList.remove("hidden")
    // The result already carries its own burnt-in HUD; leaving the preview
    // overlay up would double it.
    this.hideHudPreview()
    this.saveButtonTarget.disabled = false
    this.statusTarget.textContent = translate("video.ready", {
      size: (blob.size / (1024 * 1024)).toFixed(1),
    })
  }

  clearResult() {
    if (this.resultUrl) URL.revokeObjectURL(this.resultUrl)
    this.resultUrl = null
    this.blob = null
    this.resultTarget.removeAttribute("src")
    this.resultTarget.classList.add("hidden")
    this.drawHudPreview()
    this.saveButtonTarget.disabled = true
    this.showProgress(0, null)
  }

  setBusy(busy) {
    if (this.hasLoadButtonTarget) this.loadButtonTarget.disabled = busy
    if (this.hasDateStartTarget) this.dateStartTarget.disabled = busy
    if (this.hasDateEndTarget) this.dateEndTarget.disabled = busy
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.disabled = busy
    this.cancelButtonTarget.classList.toggle("hidden", !busy)
    this.syncRenderAvailability()
  }

  syncRenderAvailability() {
    if (!this.hasRenderButtonTarget) return
    this.renderButtonTarget.disabled = Boolean(
      this.rendering ||
        this.rangeLoading ||
        !this.style ||
        !isVideoExportSupported(),
    )
  }

  syncSupport() {
    this.syncRenderAvailability()
    if (!isVideoExportSupported()) {
      this.statusTarget.textContent = translate("video.unsupported_browser")
    }
  }

  teardown() {
    this.previewMap?.remove()
    this.previewMap = null
    this.clearResult()
  }
}
