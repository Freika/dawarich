import { formatTimestamp } from "../algorithms/geojson.js"
export function photoPopupHTML(
  feature,
  { url = "", timezone = "UTC", labels = {}, theme = "light" } = {},
) {
  const translate = (key) => labels[key] ?? key
  const {
    thumbnail_url,
    taken_at,
    filename,
    city,
    state,
    country,
    type,
    source,
  } = { ...feature.properties, thumbnail_url: url }
  const [lng, lat] = feature.geometry.coordinates

  const takenDate = taken_at
    ? formatTimestamp(taken_at, timezone)
    : translate("common.unknown")
  const location =
    [city, state, country].filter(Boolean).join(", ") ||
    translate("search.unknown_location")
  const mediaType =
    type === "VIDEO"
      ? `🎥 ${translate("map_info.video")}`
      : `📷 ${translate("map_info.photo")}`
  const popupTheme = theme
  const colors = getThemeColors(popupTheme)
  const popupHTML = `
      <div class="photo-popup" style="font-family: system-ui, -apple-system, sans-serif; max-width: min(350px, 80vw); overflow-wrap: anywhere;">
        <div style="width: 100%; border-radius: 8px; overflow: hidden; margin-bottom: 12px; background: ${colors.backgroundAlt};">
          <img
            src="${escapeAttribute(thumbnail_url)}"
            alt="${escapeAttribute(filename || translate("map_info.photo"))}"
            style="width: 100%; height: auto; max-height: 350px; object-fit: contain; display: block;"
            loading="lazy"
          />
        </div>
        <div style="font-size: 13px;">
          ${filename ? `<div style="font-weight: 600; color: ${colors.textPrimary}; margin-bottom: 6px; word-wrap: break-word;">${escapeHtml(filename)}</div>` : ""}
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📅 ${escapeHtml(takenDate)}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📍 ${escapeHtml(location)}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">${translate("map_info.coordinates")}: ${lat.toFixed(6)}, ${lng.toFixed(6)}</div>
          ${source ? `<div style="color: ${colors.textSecondary}; font-size: 11px; margin-bottom: 6px;">${translate("map_info.source")}: ${escapeHtml(source)}</div>` : ""}
          <div style="font-size: 14px; margin-top: 8px; color: ${colors.textPrimary};">${mediaType}</div>
        </div>
      </div>
    `

  return popupHTML
}

function getThemeColors(theme) {
  return theme === "dark"
    ? {
        backgroundAlt: "#374151",
        textPrimary: "#f9fafb",
        textSecondary: "#d1d5db",
        textMuted: "#9ca3af",
      }
    : {
        backgroundAlt: "#f9fafb",
        textPrimary: "#111827",
        textSecondary: "#374151",
        textMuted: "#6b7280",
      }
}

function escapeHtml(value) {
  return value == null
    ? ""
    : String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
}
function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}
