import { formatTimestamp } from '../utils/geojson_transformers'

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
          border-bottom: 1px solid #e5e7eb;
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
          background: #fef3c7;
          color: #92400e;
        }

        .visit-badge.confirmed {
          background: #d1fae5;
          color: #065f46;
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
          color: #6b7280;
        }

        .popup-row .value {
          font-weight: 500;
          color: #111827;
        }

        .popup-footer {
          padding-top: 8px;
          border-top: 1px solid #e5e7eb;
        }

        .view-details-btn {
          display: block;
          text-align: center;
          padding: 6px 12px;
          background: #3b82f6;
          color: white;
          text-decoration: none;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 500;
          transition: background 0.2s;
        }

        .view-details-btn:hover {
          background: #2563eb;
        }
      </style>
    `
  }
}
