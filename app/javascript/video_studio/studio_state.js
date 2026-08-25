// Video studio settings and the MapLibre style they derive. DOM-free on
// purpose (mirrors poster_studio): the Stimulus controller owns the DOM, this
// owns the values, and both the preview and the render read the same style.
import { resolveTheme } from "poster_studio/data/theme_loader"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import { DAWARICH_BLUE } from "video_studio/color_util"

export const VIDEO_FORMATS = {
  portrait: { width: 1080, height: 1920 },
  landscape: { width: 1920, height: 1080 },
  square: { width: 1080, height: 1080 },
}

// Matches the poster studio's default. Noir was inherited from the site
// tool and is the darkest of the seventeen — as a video it read as a
// black rectangle.
// The credit burned into the video is the project's URL, not the host this
// instance happens to answer on — a self-hosted address means nothing to
// whoever the video is shared with. Matches the poster overlay's credit.
export const DAWARICH_URL = "https://dawarich.app"

export const DEFAULT_VIDEO_THEME_KEY = "terracotta"
export const MIN_HUD_SCALE = 80
// Measured against the real HUD font: the footer's three strings stop fitting
// on one line above ~150% at the tightest aspect (short edge == width). Capped
// a step below that so the credit always has room at its full size.
export const MAX_HUD_SCALE = 140
export const MIN_DURATION_SEC = 8
export const MAX_DURATION_SEC = 30

export function defaultSettings() {
  return {
    theme: DEFAULT_VIDEO_THEME_KEY,
    format: "portrait",
    duration_sec: 15,
    camera_mode: "overview",
    follow_zoom: 13.5,
    track_color: DAWARICH_BLUE,
    track_width: 120,
    units: "km",
    hud_scale: 100,
    watermark: true,
  }
}

// Coerces whatever came back from a stored recipe into a usable settings
// object — an expired video re-rendered a release later must not blow up on a
// key that has since changed shape.
export function normalizeSettings(raw) {
  const base = defaultSettings()
  if (!raw || typeof raw !== "object") return base

  const duration = Number(raw.duration_sec)
  const followZoom = Number(raw.follow_zoom)
  // Stored as a percent, matching the poster studio's route_width. Recipes
  // written before that alignment held a 0.5-3.0 multiplier; anything at or
  // below 5 is read as one of those and scaled up rather than silently
  // becoming a hairline.
  const hudScale = Number(raw.hud_scale)
  const rawWidth = Number(raw.track_width)
  const trackWidth = rawWidth <= 5 ? rawWidth * 100 : rawWidth

  return {
    theme: typeof raw.theme === "string" ? raw.theme : base.theme,
    format: VIDEO_FORMATS[raw.format] ? raw.format : base.format,
    duration_sec: Number.isFinite(duration)
      ? Math.min(MAX_DURATION_SEC, Math.max(MIN_DURATION_SEC, duration))
      : base.duration_sec,
    camera_mode: raw.camera_mode === "follow" ? "follow" : "overview",
    follow_zoom: Number.isFinite(followZoom) ? followZoom : base.follow_zoom,
    track_color:
      typeof raw.track_color === "string" ? raw.track_color : base.track_color,
    track_width: Number.isFinite(trackWidth) ? trackWidth : base.track_width,
    units: raw.units === "mi" ? "mi" : "km",
    hud_scale: Number.isFinite(hudScale)
      ? Math.min(MAX_HUD_SCALE, Math.max(MIN_HUD_SCALE, hudScale))
      : base.hud_scale,
    watermark: raw.watermark !== false,
  }
}

// Camera contract shared by the preview and the renderer. The renderer lays
// its hidden map out at half the export size and fits the track with
// RENDER_FIT_PADDING CSS pixels of margin; the preview is a different size, so
// it has to scale that padding by the same ratio or it frames the route
// differently from the video it is previewing.
export const RENDER_FIT_PADDING = 40
export const RENDER_CSS_SCALE = 0.5

export function renderCssSize(settings) {
  const { width, height } = formatFor(settings)
  return {
    width: Math.round(width * RENDER_CSS_SCALE),
    height: Math.round(height * RENDER_CSS_SCALE),
  }
}

export function previewFitPadding(settings, previewWidth) {
  if (!previewWidth) return RENDER_FIT_PADDING
  return RENDER_FIT_PADDING * (previewWidth / renderCssSize(settings).width)
}

export function formatFor(settings) {
  return VIDEO_FORMATS[settings.format] ?? VIDEO_FORMATS.portrait
}

export function buildVideoStyle({ tokens, trackGeojson, settings }) {
  if (!tokens) return null

  return buildPosterStyle({
    theme: resolveTheme(tokens),
    trackGeojson,
    trackColor: settings.track_color,
    trackOpacity: 1,
    trackWidth: settings.track_width / 100,
  })
}
