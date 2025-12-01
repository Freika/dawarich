import { formatTimestamp } from '../utils/geojson_transformers'
import { getCurrentTheme, getThemeColors } from '../utils/popup_theme'

/**
 * Factory for creating visit popups
 */
export class VisitPopupFactory {
  /**
   * Create popup for a visit
   * @param {Object} properties - Visit properties
   * @returns {string} HTML for popup
   */
  static createVisitPopup(properties) {
    const { id, name, status, started_at, ended_at, duration, place_name } = properties

    const startTime = formatTimestamp(started_at)
    const endTime = formatTimestamp(ended_at)
    const durationHours = Math.round(duration / 3600)
    const durationDisplay = durationHours >= 1 ? `${durationHours}h` : `${Math.round(duration / 60)}m`

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    return `
      <div class="visit-popup">
        <div class="popup-header">
          <strong>${name || place_name || 'Unknown Place'}</strong>
          <span class="visit-badge ${status}">${status}</span>
        </div>
        <div class="popup-body">
          <div class="popup-row">
            <span class="label">Arrived:</span>
            <span class="value">${startTime}</span>
          </div>
          <div class="popup-row">
            <span class="label">Left:</span>
            <span class="value">${endTime}</span>
          </div>
          <div class="popup-row">
            <span class="label">Duration:</span>
            <span class="value">${durationDisplay}</span>
          </div>
        </div>
        <div class="popup-footer">
          <a href="/visits/${id}" class="view-details-btn">View Details →</a>
        </div>
      </div>

      <style>
        .visit-popup {
          font-family: system-ui, -apple-system, sans-serif;
          min-width: 250px;
        }

        .popup-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 12px;
          padding-bottom: 8px;
          border-bottom: 1px solid ${colors.border};
        }

        .visit-badge {
          padding: 2px 8px;
          border-radius: 4px;
          font-size: 10px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }

        .visit-badge.suggested {
          background: ${colors.badgeSuggested.bg};
          color: ${colors.badgeSuggested.text};
        }

        .visit-badge.confirmed {
          background: ${colors.badgeConfirmed.bg};
          color: ${colors.badgeConfirmed.text};
        }

        .popup-body {
          font-size: 13px;
          margin-bottom: 12px;
        }

        .popup-row {
          display: flex;
          justify-content: space-between;
          gap: 16px;
          padding: 4px 0;
        }

        .popup-row .label {
          color: ${colors.textMuted};
        }

        .popup-row .value {
          font-weight: 500;
          color: ${colors.textPrimary};
        }

        .popup-footer {
          padding-top: 8px;
          border-top: 1px solid ${colors.border};
        }

        .view-details-btn {
          display: block;
          text-align: center;
          padding: 6px 12px;
          background: ${colors.accent};
          color: white;
          text-decoration: none;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 500;
          transition: background 0.2s;
        }

        .view-details-btn:hover {
          background: ${colors.accentHover};
        }
      </style>
    `
  }
}
