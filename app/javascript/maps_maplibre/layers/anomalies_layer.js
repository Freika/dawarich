import { escapeHtml } from "../utils/geojson_transformers"
import { BaseLayer } from "./base_layer"

/**
 * Anomalies layer for displaying GPS noise / filtered points
 * Shows orange circle markers for points flagged as anomalies
 * Default state: OFF (hidden on load)
 */
export class AnomaliesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "anomalies", visible: false, ...options })
    this.apiClient = options.apiClient
    this.timezone = options.timezone || "UTC"
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#f97316",
          "circle-radius": 6,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ea580c",
        },
      },
    ]
  }

  /**
   * Fetch anomaly points from the API for a given date range.
   * Handles pagination to retrieve all pages.
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} GeoJSON FeatureCollection
   */
  async fetchAnomalies({ start_at, end_at }) {
    if (!this.apiClient) {
      throw new Error("API client not configured")
    }

    const allPoints = []
    let page = 1
    let totalPages = 1

    while (page <= totalPages) {
      const params = new URLSearchParams({
        start_at,
        end_at,
        anomalies_only: "true",
        page: page.toString(),
        per_page: "1000",
        slim: "true",
        order: "asc",
      })

      const response = await fetch(
        `${this.apiClient.baseURL}/points?${params}`,
        { headers: this.apiClient.getHeaders() },
      )

      if (!response.ok) {
        throw new Error(
          `Failed to fetch anomaly points: ${response.statusText}`,
        )
      }

      const points = await response.json()
      allPoints.push(...points)

      totalPages = parseInt(response.headers.get("X-Total-Pages") || "1", 10)
      page++
    }

    return this._pointsToGeoJSON(allPoints)
  }

  /**
   * Build a popup reason string for an anomaly point.
   * @param {Object} properties - Feature properties
   * @returns {string} Human-readable reason
   */
  static anomalyReason(properties) {
    const accuracy = properties.accuracy
    if (accuracy != null && accuracy > 100) {
      return `Filtered: low accuracy (${accuracy}m, threshold 100m)`
    }
    return "Filtered: impossible speed between neighboring points"
  }

  /**
   * Format a timestamp for display in popups.
   * @param {number|string} timestamp
   * @param {string} timezone
   * @returns {string}
   */
  static formatTimestamp(timestamp, timezone = "UTC") {
    let date
    if (typeof timestamp === "string") {
      date = new Date(timestamp)
    } else if (timestamp < 10000000000) {
      date = new Date(timestamp * 1000)
    } else {
      date = new Date(timestamp)
    }

    return date.toLocaleString("en-GB", {
      day: "numeric",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
      timeZone: timezone,
    })
  }

  /**
   * Build popup HTML for an anomaly point feature.
   * @param {Object} properties - Feature properties from GeoJSON
   * @returns {string} HTML content
   */
  buildPopupContent(properties) {
    const ts = AnomaliesLayer.formatTimestamp(
      properties.timestamp,
      this.timezone,
    )
    const reason = AnomaliesLayer.anomalyReason(properties)

    return `<div class="text-sm space-y-1">
      <div><strong>Time:</strong> ${escapeHtml(ts)}</div>
      <div><strong>Reason:</strong> ${escapeHtml(reason)}</div>
    </div>`
  }

  // -- private --

  /**
   * Convert raw API points into a GeoJSON FeatureCollection.
   * @param {Array} points
   * @returns {Object} GeoJSON FeatureCollection
   */
  _pointsToGeoJSON(points) {
    return {
      type: "FeatureCollection",
      features: points.map((point) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [point.longitude, point.latitude],
        },
        properties: {
          id: point.id,
          timestamp: point.timestamp,
          accuracy: point.accuracy,
          velocity: point.velocity,
        },
      })),
    }
  }
}
