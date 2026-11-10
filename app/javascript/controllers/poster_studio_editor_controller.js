import { Controller } from "@hotwired/stimulus"
import { formatDate, translate } from "i18n"
import { studioTilesUrl } from "maps_maplibre/utils/basemap_url"
import { ensurePosterFont, fontByKey } from "poster_studio/data/fonts"
import { layoutById, resolveLayoutGeometry } from "poster_studio/data/layouts"
import { detailLayersOutOfRange } from "poster_studio/data/protomaps_schema"
import { MapPageProvider } from "poster_studio/data/providers"
import { resolveTheme } from "poster_studio/data/theme_loader"
import { datePicker } from "poster_studio/editor/date_picker"
import { layoutPicker } from "poster_studio/editor/layout_picker"
import { printOutput } from "poster_studio/editor/print_output"
import { themePicker } from "poster_studio/editor/theme_picker"
import { frameCovers } from "poster_studio/render/frame_geometry"
import { drawOverlay } from "poster_studio/render/overlay"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import { formatCoords } from "poster_studio/render/text_layout"
import {
  collectCoords,
  createPreviewMap,
  trackBounds,
} from "poster_studio/ui/preview"
import Flash from "./flash_controller"

const DEFAULT_HIDDEN = ["buildings", "rail", "boundaries"]
const METERS_PER_DEGREE = 111320
// Sidecar frame semantics: it renders ±distance/3 vertically, so covering
// the studio's visible height needs distance = 3 × half-height in meters.
const SIDECAR_DISTANCE_FACTOR = 1.5
// Max lifted so any single-view framing is saveable: the distance box is
// calibrated to the visible frame, so a low cap made zoomed-out routes read as
// "outside the frame" even while visible. The upper bound stays finite to keep
// degenerate whole-globe requests off the sidecar.
const SIDECAR_DISTANCE_RANGE = [500, 5_000_000]

// Full-screen WYSIWYG poster editor: a live MapLibre map inside a
// poster-shaped frame, restyled by the same buildPosterStyle the export
// renders, with typography drawn by the same overlay pass — so what the
// preview shows is what the download produces.
export default class PosterStudioEditorController extends Controller {
  static targets = [
    "stage",
    "frame",
    "mapContainer",
    "overlay",
    "backdrop",
    "layoutSelect",
    "layoutDims",
    "swatch",
    "themeLabel",
    "token",
    "tokenValue",
    "textToggle",
    "titleInput",
    "subtitleInput",
    "coordsToggle",
    "statsToggle",
    "fontSelect",
    "detailLayersHint",
    "trackOpacity",
    "trackOpacityLabel",
    "trackWidth",
    "trackWidthLabel",
    "summary",
    "format",
    "dpi",
    "dpiField",
    "downloadButton",
    "status",
    "saveButton",
    "saveNotice",
    "saveForm",
    "saveName",
    "saveTitle",
    "saveStats",
    "saveTheme",
    "saveLat",
    "saveLon",
    "saveDistance",
    "saveStartAt",
    "saveEndAt",
    "saveSource",
    "saveOpacity",
    "saveWidth",
    "dateStart",
    "dateEnd",
    "loadButton",
    "loadSpinner",
    "loadLabel",
    "switchButton",
    "orderSection",
    "orderCta",
    "orderButton",
    "sizePicker",
    "sizePickerOptions",
    "orderDialog",
    "orderSummary",
    "orderError",
    "orderActions",
    "orderSteps",
    "orderStep",
    "uploadBar",
    "checkoutLink",
    "orderPageLink",
    "orderDoneButton",
  ]
  static values = {
    fonts: Object,
    printOrderUrl: String,
    tilesUrl: String,
    tilesFallback: Boolean,
    statsLabel: String,
  }

  connect() {
    // The map page wraps content in a z-index:20 stacking context that would
    // trap the overlay under the navbar — portal to <body>. Moving the node
    // re-runs connect (Stimulus disconnect/reconnect), hence the guard.
    if (this.element.parentElement !== document.body) {
      document.body.appendChild(this.element)
      return
    }
    this.onOpen = (event) => this.open(event.detail?.provider)
    document.addEventListener("poster-studio:open", this.onOpen)
    this.onResize = () => this.resizeFrame()
    this.populateLayouts()
    this.populateSizePicker()
    this.populateFonts()
    this.trackOpacityLabelTarget.textContent = `${this.trackOpacityTarget.value}%`
    this.trackWidthLabelTarget.textContent = `${this.trackWidthTarget.value}%`
  }

  disconnect() {
    document.removeEventListener("poster-studio:open", this.onOpen)
    this.teardown()
    if (this.backdropUrl) URL.revokeObjectURL(this.backdropUrl)
  }

  async open(provider = null) {
    if (!this.element.classList.contains("hidden")) return
    this.provider =
      provider ?? new MapPageProvider({ application: this.application })
    this.element.classList.remove("hidden")
    window.addEventListener("resize", this.onResize)

    try {
      this.hidden ??= new Set(DEFAULT_HIDDEN)
      if (!this.tokens) await this.seedTheme(this.initialThemeKey())
      if (!this.titleInputTarget.value)
        this.titleInputTarget.value = this.provider.defaultTitle()
      if (!this.subtitleInputTarget.value)
        this.subtitleInputTarget.value = this.dateRangeLabel()
      this.seedDateInputs()
      await this.provider.ensureTrackLoaded()

      this.resizeFrame()
      await this.loadFonts()
      this.createMap()
      this.updateSummary()
      this.syncOrderAvailability()
    } catch (error) {
      Flash.show(
        "error",
        translate("poster.open_failed", { error: error.message }),
      )
      this.close()
    }
  }

  close() {
    window.removeEventListener("resize", this.onResize)
    this.teardown()
    this.releaseBackdrop()
    this.element.classList.add("hidden")
  }

  // Alternate view of the same track and date range; carry the provider so a
  // trip-locked studio stays locked to that trip.
  switchToVideo() {
    if (this.rangeLoading) return
    const provider = this.provider
    this.close()
    document.dispatchEvent(
      new CustomEvent("video-studio:open", { detail: { provider } }),
    )
  }

  teardown() {
    clearTimeout(this.restyleTimer)
    this.previewMap?.remove()
    this.previewMap = null
  }

  createMap() {
    this.teardown()
    const bounds =
      trackBounds(this.trackGeojson) ?? this.provider.fallbackBounds()
    this.previewMap = createPreviewMap({
      container: this.mapContainerTarget,
      style: this.posterStyle(),
      bounds,
    })
    this.previewMap.on("move", () => this.redrawOverlay())
    this.previewMap.on("moveend", () => {
      this.syncSaveAvailability()
      this.syncDetailLayersHint()
    })
    this.previewMap.on("idle", () => this.updateBackdrop())
    this.previewMap.once("load", () => {
      this.redrawOverlay()
      this.syncSaveAvailability()
      this.syncDetailLayersHint()
    })
  }

  // Blurred ambient backdrop behind the poster frame: a snapshot of the
  // map canvas, refreshed whenever the map settles (idle covers pans,
  // zooms, restyles, and tile loads). Blob + object URL instead of a data
  // URL: async encode, no base64 strings, previous snapshot released
  // deterministically.
  updateBackdrop() {
    if (!this.hasBackdropTarget || !this.previewMap) return
    this.previewMap.getCanvas().toBlob(
      (blob) => {
        if (!blob || !this.hasBackdropTarget) return
        const previous = this.backdropUrl
        this.backdropUrl = URL.createObjectURL(blob)
        this.backdropTarget.src = this.backdropUrl
        this.backdropTarget.classList.remove("opacity-0")
        if (previous) URL.revokeObjectURL(previous)
      },
      "image/jpeg",
      0.5,
    )
  }

  releaseBackdrop() {
    if (!this.hasBackdropTarget) return
    this.backdropTarget.classList.add("opacity-0")
    this.backdropTarget.removeAttribute("src")
    if (this.backdropUrl) URL.revokeObjectURL(this.backdropUrl)
    this.backdropUrl = null
  }

  // ===== Live restyle =====

  posterStyle() {
    return buildPosterStyle({
      tileUrl: studioTilesUrl(this.tilesUrlValue, this.tilesFallbackValue),
      theme: this.resolvedTheme,
      trackGeojson: this.trackGeojson,
      extras: true,
      hiddenCategories: [...this.hidden],
      trackOpacity: this.trackOpacityValue(),
      trackWidth: this.trackWidthValue(),
    })
  }

  get resolvedTheme() {
    return resolveTheme(this.tokens)
  }

  get layout() {
    return layoutById(this.layoutSelectTarget.value)
  }

  get orderViewOpen() {
    if (!this.hasOrderDialogTarget) return false

    return (
      !this.orderDialogTarget.classList.contains("hidden") ||
      !this.sizePickerTarget.classList.contains("hidden")
    )
  }

  get fontFamily() {
    return `"${fontByKey(this.fontSelectTarget.value).family}", sans-serif`
  }

  textChanged() {
    const enabled = this.textToggleTarget.checked
    ;[
      this.titleInputTarget,
      this.subtitleInputTarget,
      this.coordsToggleTarget,
      ...this.statsToggleTargets,
      this.fontSelectTarget,
    ].forEach((el) => {
      el.disabled = !enabled
    })
    this.redrawOverlay()
  }

  async fontChanged() {
    await ensurePosterFont(this.fontSelectTarget.value, this.fontsValue)
    this.redrawOverlay()
  }

  posterText() {
    if (!this.textToggleTarget.checked)
      return { title: "", subtitle: "", coords: "", stats: "" }
    return {
      stats:
        this.hasStatsToggleTarget && this.statsToggleTarget.checked
          ? this.statsLabelValue
          : "",
      title: this.titleInputTarget.value.trim(),
      subtitle: this.subtitleInputTarget.value.trim(),
      coords: this.coordsToggleTarget.checked
        ? formatCoords(this.previewMap?.getCenter())
        : "",
    }
  }

  dateRangeLabel() {
    const { startAt, endAt } = this.provider?.dateRange() ?? {}
    if (!startAt || !endAt) return ""
    return `${formatDate(startAt)} – ${formatDate(endAt)}`
  }

  // ===== Layers =====

  layersChanged() {
    this.hidden = new Set()
    this.element.querySelectorAll("[data-layer-category]").forEach((toggle) => {
      if (!toggle.checked) this.hidden.add(toggle.dataset.layerCategory)
    })
    this.syncDetailLayersHint()
    this.trackOpacityLabelTarget.textContent = `${this.trackOpacityTarget.value}%`
    this.trackWidthLabelTarget.textContent = `${this.trackWidthTarget.value}%`
    this.scheduleRestyle()
  }

  syncDetailLayersHint() {
    if (!this.hasDetailLayersHintTarget || !this.previewMap) return
    this.detailLayersHintTarget.hidden = !detailLayersOutOfRange(
      this.previewMap.getZoom(),
      this.hidden,
    )
  }

  trackOpacityValue() {
    return Number.parseInt(this.trackOpacityTarget.value, 10) / 100
  }

  trackWidthValue() {
    return Number.parseInt(this.trackWidthTarget.value, 10) / 100
  }

  // ===== Date range =====

  recenter() {
    const bounds =
      trackBounds(this.trackGeojson) ?? this.provider.fallbackBounds()
    if (bounds) this.previewMap?.fitBounds(bounds, { padding: 24 })
  }

  // ===== Preview overlay =====

  redrawOverlay() {
    if (!this.hasOverlayTarget) return
    const canvas = this.overlayTarget
    const dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(this.frameTarget.clientWidth * dpr)
    canvas.height = Math.round(this.frameTarget.clientHeight * dpr)
    canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height)
    drawOverlay(canvas, {
      theme: this.resolvedTheme,
      ...this.posterText(),
      font: this.fontFamily,
    })
  }

  // ===== Export =====

  saveToGallery() {
    if (!this.previewMap || this.saveButtonTarget.disabled) return
    const center = this.previewMap.getCenter()
    const distance = this.sidecarDistance()

    // The typed title is what gets drawn on the poster (blank ⇒ no title);
    // the gallery name is a separate required label that falls back to a
    // neutral placeholder so an untitled poster never reads "MY POSTER".
    const title = this.titleInputTarget.value.trim()
    this.saveTitleTarget.value = title
    this.saveStatsTarget.value = this.posterText().stats
    this.saveNameTarget.value = title || translate("poster.untitled")
    this.saveThemeTarget.value = this.themeBase || "blueprint"
    this.saveLatTarget.value = center.lat
    this.saveLonTarget.value = center.lng
    this.saveDistanceTarget.value = distance
    const { startAt, endAt } = this.provider.dateRange()
    this.saveStartAtTarget.value = startAt || ""
    this.saveEndAtTarget.value = endAt || ""
    this.saveSourceTarget.value = this.provider.trackSource()
    this.saveOpacityTarget.value = this.trackOpacityTarget.value
    this.saveWidthTarget.value = this.trackWidthTarget.value
    this.saveFormTarget.requestSubmit()
    this.setStatus(translate("poster.queued"))
  }

  framedDistance() {
    const bounds = this.previewMap.getBounds()
    const heightMeters =
      (bounds.getNorth() - bounds.getSouth()) * METERS_PER_DEGREE
    return heightMeters * SIDECAR_DISTANCE_FACTOR
  }

  sidecarDistance() {
    const [min, max] = SIDECAR_DISTANCE_RANGE
    return Math.round(Math.min(max, Math.max(min, this.framedDistance())))
  }

  frameIsClamped() {
    const [, max] = SIDECAR_DISTANCE_RANGE
    return this.framedDistance() > max
  }

  // The server refuses renders without track data in the frame — mirror
  // both guards here so Save to gallery can't queue a doomed poster.
  syncSaveAvailability() {
    if (!this.hasSaveButtonTarget || !this.previewMap) return
    // Gallery renders are rebuilt server-side from GPS, without flight overlays.
    const coords = collectCoords(this.provider?.trackGeojson())
    let reason = null
    if (coords.length === 0) {
      reason = translate("poster.no_location_data")
    } else if (!this.frameCoversTrack(coords)) {
      reason = translate("poster.no_tracks_in_frame")
    }
    const posterGeometry = this.provider?.posterGeojson?.()
    const overlayNotice =
      posterGeometry && posterGeometry !== this.provider.trackGeojson()
        ? translate("poster.gallery_without_flights")
        : null
    const message = [
      reason ||
        (this.frameIsClamped() ? translate("poster.frame_too_wide") : null),
      overlayNotice,
    ]
      .filter(Boolean)
      .join(" ")
    this.saveButtonTarget.disabled = Boolean(reason)
    this.saveNoticeTarget.textContent = message || ""
    this.saveNoticeTarget.classList.toggle("hidden", !message)
  }

  // Mirrors the server's track_intersects_area?.
  frameCoversTrack(coords) {
    const center = this.previewMap.getCenter()

    return frameCovers(coords, center.lat, center.lng, this.sidecarDistance())
  }

  updateSummary() {
    const layout = this.layout
    const dpi = Number.parseInt(this.dpiTarget.value, 10)
    const geometry = resolveLayoutGeometry(layout, dpi)
    const lines = [
      `${translate(`poster.layouts.${layout.id}`)} — ${layout.dimensionsLabel}`,
      `Theme: ${this.themeName || "—"}`,
      `Export: ${geometry.width} × ${geometry.height}px${
        layout.kind === "paper" ? ` @ ${geometry.effectiveDpi} dpi` : ""
      }`,
    ]
    this.summaryTarget.textContent = lines.join(" · ")
  }

  // ===== Data plumbing =====

  get trackGeojson() {
    return (
      this.provider?.posterGeojson?.() ??
      this.provider?.trackGeojson() ?? {
        type: "FeatureCollection",
        features: [],
      }
    )
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  setBusy(value) {
    this.busy = value
    this.downloadButtonTarget.disabled = value
  }
}

Object.assign(
  PosterStudioEditorController.prototype,
  printOutput,
  themePicker,
  layoutPicker,
  datePicker,
)
