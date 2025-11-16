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
}
