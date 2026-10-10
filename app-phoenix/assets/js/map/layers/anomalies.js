import { createRequestScope } from "../data/request_scope.js"
import { BaseLayer } from "./base.js"

export class AnomaliesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "anomalies", visible: false, ...options })
    this.reader = options.reader
    this.operations = createRequestScope(options.timers)
    this.labels = options.labels ?? {}
    this.onError = options.onError
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

  async fetchAnomalies(params, { signal } = {}) {
    this.operations.reset()
    const operation = this.operations.begin(signal)
    try {
      const points = await operation.wait(
        this.reader.pages(
          "points",
          { ...params, anomalies_only: "true", slim: "true", order: "asc" },
          { signal: operation.signal },
        ),
      )
      operation.check()
      return this._pointsToGeoJSON(points)
    } catch (error) {
      if (
        error.name !== "AbortError" ||
        (operation.revision === this.operations.revision && !signal?.aborted)
      )
        this.onError?.("anomalies_load_failed")
      throw error
    } finally {
      operation.close()
    }
  }
  remove() {
    this.operations.destroy()
    super.remove()
  }

  static anomalyReason(properties, labels = {}) {
    const accuracy = properties.accuracy
    if (accuracy != null && accuracy > 100) {
      return (
        labels["anomalies.low_accuracy"] ??
        "Low accuracy: {accuracy} m (threshold {threshold} m)"
      )
        .replace("{accuracy}", accuracy)
        .replace("{threshold}", 100)
    }
    return labels["anomalies.impossible_speed"] ?? "Impossible speed"
  }

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

  buildPopupContent(properties) {
    const ts = AnomaliesLayer.formatTimestamp(
      properties.timestamp,
      this.timezone,
    )
    const reason = AnomaliesLayer.anomalyReason(properties, this.labels)

    return `<div class="text-sm space-y-1">
      <div><strong>${escapeHtml(this.labels["map_info.time"] ?? "Time")}:</strong> ${escapeHtml(ts)}</div>
      <div><strong>${escapeHtml(this.labels["map_info.reason"] ?? "Reason")}:</strong> ${escapeHtml(reason)}</div>
    </div>`
  }

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

function escapeHtml(value) {
  return value == null
    ? ""
    : String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
}
