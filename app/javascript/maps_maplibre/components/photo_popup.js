import { translate } from "i18n"
import { escapeHtml, formatTimestamp } from "../utils/geojson_transformers"

function escapeAttr(value) {
  return escapeHtml(value).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

/**
 * Factory for creating photo popups
 */
export class PhotoPopupFactory {
  /**
   * Create popup for a photo
   * @param {Object} properties - Photo properties
   * @param {string} timezone - IANA timezone string (e.g. "Europe/London")
   * @returns {string} HTML for popup
   */
  static createPhotoPopup(properties, timezone = "UTC") {
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

    return `
      <div class="photo-popup">
        <div class="photo-preview">
          <img src="${escapeAttr(thumbnail_url)}"
               alt="${escapeAttr(filename)}"
               loading="lazy">
        </div>
        <div class="photo-info">
          <div class="filename">${escapeHtml(filename)}</div>
          <div class="timestamp">${translate("map_info.taken")}: ${escapeHtml(takenDate)}</div>
          <div class="location">${translate("map_info.location")}: ${escapeHtml(location)}</div>
          <div class="source">${translate("map_info.source")}: ${escapeHtml(source)}</div>
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
