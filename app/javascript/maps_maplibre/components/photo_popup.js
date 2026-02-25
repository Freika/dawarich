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
    const {
      thumbnail_url,
      taken_at,
      filename,
      city,
      state,
      country,
      type,
      source,
    } = properties

    const takenDate = taken_at ? new Date(taken_at).toLocaleString() : "Unknown"
    const location =
      [city, state, country].filter(Boolean).join(", ") || "Unknown location"
    const mediaType = type === "VIDEO" ? "🎥 Video" : "📷 Photo"

    return `
      <div class="photo-popup">
        <div class="photo-preview">
          <img src="${thumbnail_url}"
               alt="${filename}"
               loading="lazy">
        </div>
        <div class="photo-info">
          <div class="filename">${filename}</div>
          <div class="timestamp">Taken: ${takenDate}</div>
          <div class="location">Location: ${location}</div>
          <div class="source">Source: ${source}</div>
          <div class="media-type">${mediaType}</div>
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
        }

        .photo-info > div {
          margin-bottom: 6px;
        }

        .photo-info .filename {
          font-weight: 600;
          color: #111827;
        }

        .photo-info .timestamp {
          color: #6b7280;
          font-size: 12px;
        }

        .photo-info .location {
          color: #6b7280;
          font-size: 12px;
        }

        .photo-info .source {
          color: #9ca3af;
          font-size: 11px;
        }

        .photo-info .media-type {
          font-size: 14px;
          margin-top: 8px;
        }
      </style>
    `
  }
}
