import { BaseLayer } from "./base_layer"
import { heatmapPaint } from "./heatmap_layer"

/**
 * Read-only vector-tile points layer for parity/performance validation.
 */
export class PointsMvtLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "points-mvt", ...options })
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.apiKey = options.apiKey || null
    this._tileUrl = null
    this._cacheBuster = 0
    // Heatmap rides the same source and same lifecycle, toggled independently
    this.heatmapVisible = options.heatmapVisible === true
  }

  static HEATMAP_LAYER_ID = "points-mvt-heatmap"

  setHeatmapVisible(visible) {
    this.heatmapVisible = visible
    this._applyLayerVisibility(PointsMvtLayer.HEATMAP_LAYER_ID, visible)
  }

  // Sub-layers are toggled independently, so they cannot share BaseLayer's flag
  setVisibility(visible) {
    this.visible = visible
    this._applyLayerVisibility(this.id, visible)
    this._applyLayerVisibility(
      PointsMvtLayer.HEATMAP_LAYER_ID,
      this.heatmapVisible,
    )
  }

  _applyLayerVisibility(layerId, visible) {
    if (!this.map.getLayer(layerId)) return

    this.map.setLayoutProperty(
      layerId,
      "visibility",
      visible ? "visible" : "none",
    )
  }

  // MapLibre caches tiles by URL, so bump a nonce to force a re-fetch.
  refresh() {
    this._cacheBuster += 1

    const wasVisible = this.visible
    this.remove()
    this.add({ startAt: this.startAt, endAt: this.endAt })
    this.setVisibility(wasVisible)
  }

  getSourceConfig() {
    this._tileUrl = this._buildTileUrl()

    return {
      type: "vector",
      tiles: [this._tileUrl],
      minzoom: 0,
      maxzoom: 22,
    }
  }

  getLayerConfigs() {
    return [
      {
        id: PointsMvtLayer.HEATMAP_LAYER_ID,
        type: "heatmap",
        source: this.sourceId,
        "source-layer": "points",
        paint: heatmapPaint(),
      },
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        "source-layer": "points",
        paint: {
          "circle-color": "#3b82f6",
          "circle-radius": 6,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  update(options = {}) {
    const nextStartAt = options.startAt || null
    const nextEndAt = options.endAt || null
    const nextTileUrl = this._buildTileUrl(nextStartAt, nextEndAt)

    if (this._tileUrl === nextTileUrl) {
      this.startAt = nextStartAt
      this.endAt = nextEndAt
      return
    }

    const wasVisible = this.visible
    this.remove()
    this.startAt = nextStartAt
    this.endAt = nextEndAt
    this.add(options)
    this.setVisibility(wasVisible)
  }

  _buildTileUrl(startAt = this.startAt, endAt = this.endAt) {
    const params = new URLSearchParams()

    if (startAt) params.set("start_at", startAt)
    if (endAt) params.set("end_at", endAt)
    if (this.apiKey) params.set("api_key", this.apiKey)
    if (this._cacheBuster) params.set("_", String(this._cacheBuster))

    const query = params.toString()
    const path = "/api/v1/tiles/points/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }
}
