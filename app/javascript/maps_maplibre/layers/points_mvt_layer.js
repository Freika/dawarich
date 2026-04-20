import { BaseLayer } from "./base_layer"

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

    const query = params.toString()
    const path = "/api/v1/tiles/points/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }
}
