import { formatTimestamp } from "../utils/geojson_transformers"
import { getCurrentTheme, getThemeColors } from "../utils/popup_theme"

/**
 * Factory for creating map popups
 */
export class PopupFactory {
  /**
   * Create popup for a point
   * @param {Object} properties - Point properties
   * @returns {string} HTML for popup
   */
  static createPointPopup(properties) {
    const { id, timestamp, altitude, battery, accuracy, velocity } = properties

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    return `
      <div class="point-popup" style="color: ${colors.textPrimary};">
        <div class="popup-header" style="border-bottom: 1px solid ${colors.border};">
          <strong>Point #${id}</strong>
        </div>
        <div class="popup-body">
          <div class="popup-row">
            <span class="label" style="color: ${colors.textMuted};">Time:</span>
            <span class="value" style="color: ${colors.textPrimary};">${formatTimestamp(timestamp)}</span>
          </div>
          ${
            altitude
              ? `
            <div class="popup-row">
              <span class="label" style="color: ${colors.textMuted};">Altitude:</span>
              <span class="value" style="color: ${colors.textPrimary};">${Math.round(altitude)}m</span>
            </div>
          `
              : ""
          }
          ${
            battery
              ? `
            <div class="popup-row">
              <span class="label" style="color: ${colors.textMuted};">Battery:</span>
              <span class="value" style="color: ${colors.textPrimary};">${battery}%</span>
            </div>
          `
              : ""
          }
          ${
            accuracy
              ? `
            <div class="popup-row">
              <span class="label" style="color: ${colors.textMuted};">Accuracy:</span>
              <span class="value" style="color: ${colors.textPrimary};">${Math.round(accuracy)}m</span>
            </div>
          `
              : ""
          }
          ${
            velocity
              ? `
            <div class="popup-row">
              <span class="label" style="color: ${colors.textMuted};">Speed:</span>
              <span class="value" style="color: ${colors.textPrimary};">${Math.round(velocity * 3.6)} km/h</span>
            </div>
          `
              : ""
          }
        </div>
      </div>
    `
  }

  /**
   * Create popup for a place
   * @param {Object} properties - Place properties
   * @returns {string} HTML for popup
   */
  static createPlacePopup(properties) {
    const { id, name, latitude, longitude, note, tags } = properties

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    // Parse tags if they're stringified
    let parsedTags = tags
    if (typeof tags === "string") {
      try {
        parsedTags = JSON.parse(tags)
      } catch (_e) {
        parsedTags = []
      }
    }

    // Format tags as badges
    const tagsHtml =
      parsedTags && Array.isArray(parsedTags) && parsedTags.length > 0
        ? parsedTags
            .map(
              (tag) => `
          <span class="badge badge-sm" style="background-color: ${tag.color}; color: white;">
            ${tag.icon} #${tag.name}
          </span>
        `,
            )
            .join(" ")
        : `<span class="badge badge-sm badge-outline" style="border-color: ${colors.border}; color: ${colors.textMuted};">Untagged</span>`

    return `
      <div class="place-popup" style="color: ${colors.textPrimary};">
        <div class="popup-header" style="border-bottom: 1px solid ${colors.border};">
          <strong>${name || `Place #${id}`}</strong>
        </div>
        <div class="popup-body">
          ${
            note
              ? `
            <div class="popup-row">
              <span class="label" style="color: ${colors.textMuted};">Note:</span>
              <span class="value" style="color: ${colors.textPrimary};">${note}</span>
            </div>
          `
              : ""
          }
          <div class="popup-row">
            <span class="label" style="color: ${colors.textMuted};">Tags:</span>
            <div class="value">${tagsHtml}</div>
          </div>
          <div class="popup-row">
            <span class="label" style="color: ${colors.textMuted};">Coordinates:</span>
            <span class="value" style="color: ${colors.textPrimary};">${latitude.toFixed(5)}, ${longitude.toFixed(5)}</span>
          </div>
        </div>
      </div>
    `
  }
}
