import { translate } from "i18n"
import { escapeHtml } from "../utils/geojson_transformers"
import { BaseLayer } from "./base_layer"

/**
 * Anomalies layer for displaying GPS noise / filtered points
 * Shows orange circle markers for points flagged as anomalies
 * Default state: OFF (hidden on load)
 */
// FNV-1a cache partitioner, same non-secret scheme as the other tile layers —
// auth travels only in the Authorization header via the map transformRequest.
function anomalyCachePartitioner(value) {
  let hash = 0x811c9dc5
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return (hash >>> 0).toString(16)
}

export class AnomaliesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "anomalies", visible: false, ...options })
    this.apiClient = options.apiClient
    this.timezone = options.timezone || "UTC"
    // Tiled mode replaces the self-paginating bulk fetch (the same unbounded
    // download the points layer abandoned) with the anomalies tile endpoint.
    this.tiled = options.tiled === true
    this.apiKey = options.apiKey || null
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
  }

  getSourceConfig() {
    if (this.tiled) {
      return {
        type: "vector",
        tiles: [this._buildTileUrl()],
        minzoom: 0,
        maxzoom: 22,
      }
    }

    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  // Switches source mode in place (the source type is fixed at add time, so a
  // mode change needs a remove/re-add cycle). Visibility survives the swap.
  setTiled(tiled, { startAt, endAt } = {}) {
    const nextTiled = tiled === true
    const rangeChanged =
      startAt !== undefined &&
      (startAt !== this.startAt || endAt !== this.endAt)
    if (nextTiled === this.tiled && !rangeChanged) return

    this.tiled = nextTiled
    if (startAt !== undefined) this.startAt = startAt
    if (endAt !== undefined) this.endAt = endAt

    if (!this.map.getSource(this.sourceId)) return

    const wasVisible = this.visible
    this.remove()
    this.add(this.data || { type: "FeatureCollection", features: [] })
    this.setVisibility(wasVisible)
  }

  _buildTileUrl() {
    const params = new URLSearchParams()

    if (this.startAt) params.set("start_at", this.startAt)
    if (this.endAt) params.set("end_at", this.endAt)
    // Never the raw api key: the Bearer header authenticates (transformRequest)
    if (this.apiKey) params.set("u", anomalyCachePartitioner(this.apiKey))

    const query = params.toString()
    const path = "/api/v1/tiles/anomalies/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }

  getLayerConfigs() {
    const config = {
      id: this.id,
      type: "circle",
      source: this.sourceId,
      paint: {
        "circle-color": "#f97316",
        "circle-radius": 6,
        "circle-stroke-width": 2,
        "circle-stroke-color": "#ea580c",
      },
    }
    // The anomalies endpoint reuses the points tile query, so the MVT layer
    // inside the tile is named 'points'.
    if (this.tiled) config["source-layer"] = "points"

    return [config]
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
      return translate("anomalies.low_accuracy", { accuracy, threshold: 100 })
    }
    return translate("anomalies.impossible_speed")
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
      <div><strong>${translate("map_info.time")}:</strong> ${escapeHtml(ts)}</div>
      <div><strong>${translate("map_info.reason")}:</strong> ${escapeHtml(reason)}</div>
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
