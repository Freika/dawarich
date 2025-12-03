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
          min-width: 280px;
        }

        .popup-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 16px;
          padding-bottom: 12px;
          border-bottom: 1px solid ${colors.border};
          gap: 12px;
        }

        .popup-header strong {
          font-size: 15px;
          flex: 1;
        }

        .visit-badge {
          padding: 4px 8px;
          border-radius: 4px;
          font-size: 10px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          white-space: nowrap;
          flex-shrink: 0;
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
          margin-bottom: 16px;
        }

        .popup-row {
          margin-bottom: 10px;
        }

        .popup-row .label {
          color: ${colors.textMuted};
          display: block;
          margin-bottom: 4px;
          font-size: 12px;
        }

        .popup-row .value {
          font-weight: 500;
          color: ${colors.textPrimary};
          display: block;
        }

        .popup-footer {
          padding-top: 12px;
          border-top: 1px solid ${colors.border};
        }

        .view-details-btn {
          display: block;
          text-align: center;
          padding: 10px 16px;
          background: ${colors.accent};
          color: white;
          text-decoration: none;
          border-radius: 6px;
          font-size: 14px;
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
