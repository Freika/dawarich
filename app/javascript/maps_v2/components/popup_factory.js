import { formatTimestamp } from '../utils/geojson_transformers'

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

    return `
      <div class="point-popup">
        <div class="popup-header">
          <strong>Point #${id}</strong>
        </div>
        <div class="popup-body">
          <div class="popup-row">
            <span class="label">Time:</span>
            <span class="value">${formatTimestamp(timestamp)}</span>
          </div>
          ${altitude ? `
            <div class="popup-row">
              <span class="label">Altitude:</span>
              <span class="value">${Math.round(altitude)}m</span>
            </div>
          ` : ''}
          ${battery ? `
            <div class="popup-row">
              <span class="label">Battery:</span>
              <span class="value">${battery}%</span>
            </div>
          ` : ''}
          ${accuracy ? `
            <div class="popup-row">
              <span class="label">Accuracy:</span>
              <span class="value">${Math.round(accuracy)}m</span>
            </div>
          ` : ''}
          ${velocity ? `
            <div class="popup-row">
              <span class="label">Speed:</span>
              <span class="value">${Math.round(velocity * 3.6)} km/h</span>
            </div>
          ` : ''}
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

    // Parse tags if they're stringified
    let parsedTags = tags
    if (typeof tags === 'string') {
      try {
        parsedTags = JSON.parse(tags)
      } catch (e) {
        parsedTags = []
      }
    }

    // Format tags as badges
    const tagsHtml = parsedTags && Array.isArray(parsedTags) && parsedTags.length > 0
      ? parsedTags.map(tag => `
          <span class="badge badge-sm" style="background-color: ${tag.color}; color: white;">
            ${tag.icon} #${tag.name}
          </span>
        `).join(' ')
      : '<span class="badge badge-sm badge-outline">Untagged</span>'

    return `
      <div class="place-popup">
        <div class="popup-header">
          <strong>${name || `Place #${id}`}</strong>
        </div>
        <div class="popup-body">
          ${note ? `
            <div class="popup-row">
              <span class="label">Note:</span>
              <span class="value">${note}</span>
            </div>
          ` : ''}
          <div class="popup-row">
            <span class="label">Tags:</span>
            <div class="value">${tagsHtml}</div>
          </div>
          <div class="popup-row">
            <span class="label">Coordinates:</span>
            <span class="value">${latitude.toFixed(5)}, ${longitude.toFixed(5)}</span>
          </div>
        </div>
      </div>
    `
  }
}
