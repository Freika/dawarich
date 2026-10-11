import { DAWARICH_BLUE } from "./color_util.js"

export const VIDEO_FORMATS = {
  portrait: { width: 1080, height: 1920 },
  landscape: { width: 1920, height: 1080 },
  square: { width: 1080, height: 1080 },
}

const validFormat = (format) =>
  typeof format === "string" && Object.hasOwn(VIDEO_FORMATS, format)

export const DAWARICH_URL = "https://dawarich.app"

export const DEFAULT_VIDEO_THEME_KEY = "terracotta"
export const MIN_HUD_SCALE = 80
export const MAX_HUD_SCALE = 140
export const MIN_DURATION_SEC = 8
export const MAX_DURATION_SEC = 30
export const MIN_TRACK_WIDTH = 50
export const MAX_TRACK_WIDTH = 300
export const MIN_FOG_OPACITY = 0
export const MAX_FOG_OPACITY = 100

export function defaultSettings() {
  return {
    theme: DEFAULT_VIDEO_THEME_KEY,
    format: "portrait",
    duration_sec: 15,
    camera_mode: "overview",
    follow_zoom: 13.5,
    track_color: DAWARICH_BLUE,
    track_width: 120,
    visualization_mode: "route",
    fog_opacity: 65,
    fog_color: "#000000",
    show_marker: true,
    show_route: true,
    units: "km",
    hud_scale: 100,
    watermark: true,
  }
}

export function normalizeSettings(raw) {
  const base = defaultSettings()
  if (!raw || typeof raw !== "object") return base

  const duration = Number(raw.duration_sec)
  const followZoom = Number(raw.follow_zoom)
  const hudScale = Number(raw.hud_scale)
  const rawWidth = Number(raw.track_width)
  const trackWidth = rawWidth <= 5 ? rawWidth * 100 : rawWidth
  const fogOpacity = Number(raw.fog_opacity)

  return {
    theme: typeof raw.theme === "string" ? raw.theme : base.theme,
    format: validFormat(raw.format) ? raw.format : base.format,
    duration_sec: Number.isFinite(duration)
      ? Math.min(MAX_DURATION_SEC, Math.max(MIN_DURATION_SEC, duration))
      : base.duration_sec,
    camera_mode: raw.camera_mode === "follow" ? "follow" : "overview",
    follow_zoom: Number.isFinite(followZoom) ? followZoom : base.follow_zoom,
    track_color:
      typeof raw.track_color === "string" ? raw.track_color : base.track_color,
    track_width: Number.isFinite(trackWidth)
      ? Math.min(MAX_TRACK_WIDTH, Math.max(MIN_TRACK_WIDTH, trackWidth))
      : base.track_width,
    visualization_mode: raw.visualization_mode === "fog" ? "fog" : "route",
    fog_opacity: Number.isFinite(fogOpacity)
      ? Math.min(MAX_FOG_OPACITY, Math.max(MIN_FOG_OPACITY, fogOpacity))
      : base.fog_opacity,
    fog_color: /^#[0-9a-f]{6}$/i.test(raw.fog_color || "")
      ? raw.fog_color
      : base.fog_color,
    show_marker: raw.show_marker !== false && raw.show_marker !== "false",
    show_route: raw.show_route !== false && raw.show_route !== "false",
    units: raw.units === "mi" ? "mi" : "km",
    hud_scale: Number.isFinite(hudScale)
      ? Math.min(MAX_HUD_SCALE, Math.max(MIN_HUD_SCALE, hudScale))
      : base.hud_scale,
    watermark: raw.watermark !== false && raw.watermark !== "false",
  }
}

export function provenanceOf(view) {
  const { startAt, endAt } = view?.range ?? {}
  return {
    source: view?.fixed === true ? "trip" : "map",
    start_at: startAt || "",
    end_at: endAt || "",
  }
}

export function readProvenance(raw) {
  if (!raw || typeof raw !== "object") return null
  const startAt = typeof raw.start_at === "string" ? raw.start_at : ""
  const endAt = typeof raw.end_at === "string" ? raw.end_at : ""
  if (!startAt && !endAt) return null

  return {
    source: raw.source === "trip" ? "trip" : "map",
    start_at: startAt,
    end_at: endAt,
  }
}

export function rangeRestorePlan(provenance, showing, view) {
  if (!provenance) return { action: "none" }
  if (
    provenance.start_at === showing.startAt &&
    provenance.end_at === showing.endAt
  ) {
    return { action: "none" }
  }

  const range = [provenance.start_at, provenance.end_at]
    .filter(Boolean)
    .join(" - ")
  const reachable = view?.fixed === false && provenance.source !== "trip"

  return reachable
    ? {
        action: "navigate",
        start_at: provenance.start_at,
        end_at: provenance.end_at,
        range,
      }
    : { action: "warn", range }
}

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
  return VIDEO_FORMATS[
    validFormat(settings.format) ? settings.format : "portrait"
  ]
}

export function buildVideoStyle(
  { tokens, trackGeojson, settings },
  { buildPosterStyle, resolveTheme },
) {
  if (!tokens) return null

  return buildPosterStyle({
    theme: resolveTheme(tokens),
    trackGeojson,
    trackColor: settings.track_color,
    trackOpacity: settings.show_route ? 1 : 0,
    trackWidth: settings.track_width / 100,
  })
}
