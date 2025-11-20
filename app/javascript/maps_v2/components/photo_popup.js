/**
 * Factory for creating photo popups
 */
export class PhotoPopupFactory {
  /**
   * Create popup for a photo
   * @param {Object} properties - Photo properties
   * @returns {string} HTML for popup
   */
  static createPhotoPopup(properties) {
    const { id, thumbnail_url, url, taken_at, camera, location_name } = properties

    const takenDate = taken_at ? new Date(taken_at * 1000).toLocaleString() : null

    return `
      <div class="photo-popup">
        <div class="photo-preview">
          <img src="${url || thumbnail_url}"
               alt="Photo"
               loading="lazy"
               onerror="this.src='${thumbnail_url}'">
        </div>
        <div class="photo-info">
          ${location_name ? `<div class="location">${location_name}</div>` : ''}
          ${takenDate ? `<div class="timestamp">${takenDate}</div>` : ''}
          ${camera ? `<div class="camera">${camera}</div>` : ''}
        </div>
        <div class="photo-actions">
          <a href="${url}" target="_blank" class="view-full-btn">View Full Size →</a>
        </div>
      </div>

      <style>
        .photo-popup {
          font-family: system-ui, -apple-system, sans-serif;
          max-width: 300px;
        }

        .photo-preview {
          width: 100%;
          border-radius: 8px;
          overflow: hidden;
          margin-bottom: 12px;
          background: #f3f4f6;
        }

        .photo-preview img {
          width: 100%;
          height: auto;
          max-height: 300px;
          object-fit: cover;
          display: block;
        }

        .photo-info {
          font-size: 13px;
          margin-bottom: 12px;
        }

        .photo-info .location {
          font-weight: 600;
          color: #111827;
          margin-bottom: 4px;
        }

        .photo-info .timestamp {
          color: #6b7280;
          font-size: 12px;
          margin-bottom: 4px;
        }

        .photo-info .camera {
          color: #9ca3af;
          font-size: 11px;
        }

        .photo-actions {
          padding-top: 8px;
          border-top: 1px solid #e5e7eb;
        }

        .view-full-btn {
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

        .view-full-btn:hover {
          background: #2563eb;
        }
      </style>
    `
  }
}
