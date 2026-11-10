import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { studioTilesUrl } from "maps_maplibre/utils/basemap_url"
import { loadThemeTokens } from "poster_studio/data/theme_loader"
import { trackBounds } from "poster_studio/ui/preview"
import { drawHud } from "video_studio/hud_overlay"
import { drawFogOverlay, drawRouteMarker } from "video_studio/map_effects"
import { sliceAtFraction } from "video_studio/route_timeline"
import {
  buildVideoStyle,
  DAWARICH_URL,
  formatFor,
  previewFitPadding,
} from "video_studio/studio_state"
import { buildStatRows } from "video_studio/video_stats"

const HUD_PREVIEW_FRACTION = 0.62

/**
 * Video studio live preview: map style, frame size, HUD and stats.
 * Mixed into the controller; `this` is the controller.
 */
export const preview = {
  async refreshStyle(operation = null) {
    const tokens = await loadThemeTokens(this.settings.theme)
    if (operation !== null && !this.operationIsCurrent(operation)) return
    this.themeTokens = tokens
    this.style = buildVideoStyle({
      tokens,
      trackGeojson: this.trackGeojson,
      settings: this.settings,
      tileUrl: studioTilesUrl(this.tilesUrlValue, this.tilesFallbackValue),
    })
    this.drawPreview()
  },

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
  },

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

    const slice = sliceAtFraction(this.timeline, HUD_PREVIEW_FRACTION)
    if (this.settings.visualization_mode === "fog") {
      drawFogOverlay(ctx, {
        map: this.previewMap,
        features: slice.features,
        head: slice.head,
        width: canvas.width,
        height: canvas.height,
        opacity: this.settings.fog_opacity / 100,
        color: this.settings.fog_color,
      })
    }
    if (this.settings.show_marker) {
      drawRouteMarker(ctx, {
        map: this.previewMap,
        coordinate: slice.head,
        width: canvas.width,
        height: canvas.height,
        accent: this.settings.track_color,
      })
    }

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
  },

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
    this.previewMap.once("idle", () => this.drawHudPreview())
  },

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
  },

  fitPreview(bounds) {
    if (!bounds || !this.previewMap) return
    this.previewMap.fitBounds(bounds, this.fitOptions())
  },

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
  },
}
