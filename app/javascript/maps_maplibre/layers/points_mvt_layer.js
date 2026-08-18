import { getMarkerStrokeColor } from "../utils/marker_theme"
import { BaseLayer } from "./base_layer"
import { heatmapPaint } from "./heatmap_layer"

// FNV-1a over the api key: a non-secret cache partitioner keying URL-based
// caches per user — auth itself travels only in the Authorization header.
function cachePartitioner(value) {
  let hash = 0x811c9dc5
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return (hash >>> 0).toString(16)
}

/**
 * Read-only vector-tile points layer for parity/performance validation.
 */
export class PointsMvtLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "points-mvt", ...options })
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.apiKey = options.apiKey || null
    this.styleName = options.styleName
    this._tileUrl = null
    this._cacheBuster = 0
    // Heatmap rides the same source and same lifecycle, toggled independently
    this.heatmapVisible = options.heatmapVisible === true
    this.onTileError = options.onTileError || null
    this._tileErrorHandler = null
    this._tileErrorReported = false
  }

  // A failed tile fetch (timeout, throttle, expired session) reaches the page
  // only as a map `error` event. Unwatched, the layer just renders nothing and
  // the classic layer is hidden — an empty map with no explanation.
  add(data, beforeId = null) {
    super.add(data, beforeId)
    this._tileErrorReported = false
    this._watchTileErrors()
  }

  remove() {
    this._unwatchTileErrors()
    super.remove()
  }

  _watchTileErrors() {
    if (this._tileErrorHandler || !this.onTileError) return

    this._tileErrorHandler = (event) => {
      if (event?.sourceId !== this.sourceId) return
      // One pan fails a whole screenful of tiles; report the episode once.
      if (this._tileErrorReported) return

      this._tileErrorReported = true
      this.onTileError(event)
    }
    this.map.on("error", this._tileErrorHandler)
  }

  _unwatchTileErrors() {
    if (!this._tileErrorHandler) return

    this.map.off("error", this._tileErrorHandler)
    this._tileErrorHandler = null
  }

  static HEATMAP_LAYER_ID = "points-mvt-heatmap"

  setHeatmapVisible(visible) {
    this.heatmapVisible = visible
    this._applyLayerVisibility(PointsMvtLayer.HEATMAP_LAYER_ID, visible)
  }

  // The circle and heatmap sub-layers toggle independently; anything keyed to
  // "is this layer on screen" must consider both.
  get anyVisible() {
    return Boolean(this.visible || this.heatmapVisible)
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

  // ⛔ MapLibre loads NO tiles for a source whose layers are all layout-hidden
  // (Style.update marks it unused and SourceCache evicts). Tiled fog reads
  // this source via querySourceFeatures, so while fog depends on it the circle
  // layer hides via PAINT (opacity 0) — isHidden() keys on layout visibility,
  // keeping the source used and its tiles loading.
  setSourceKeepAlive(keepAlive) {
    this.sourceKeepAlive = keepAlive === true
    this.setVisibility(this.visible)
  }

  _applyLayerVisibility(layerId, visible) {
    if (!this.map.getLayer(layerId)) return

    if (layerId === this.id && !visible && this.sourceKeepAlive) {
      this.map.setLayoutProperty(layerId, "visibility", "visible")
      this.map.setPaintProperty?.(layerId, "circle-opacity", 0)
      this.map.setPaintProperty?.(layerId, "circle-stroke-opacity", 0)
      this._paintHidden = true
      return
    }
    if (layerId === this.id && this._paintHidden) {
      this.map.setPaintProperty?.(layerId, "circle-opacity", 1)
      this.map.setPaintProperty?.(layerId, "circle-stroke-opacity", 1)
      this._paintHidden = false
    }

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
    const beforeId = this._layerAbove()
    this.remove()
    this.add({ startAt: this.startAt, endAt: this.endAt }, beforeId)
    this.setVisibility(wasVisible)
  }

  // The id of the layer stacked directly above this one, so a remove+add
  // cycle can put the sub-layers back where they were instead of on top.
  _layerAbove() {
    const styleLayers = this.map.getStyle?.()?.layers ?? []
    const ownIds = new Set([PointsMvtLayer.HEATMAP_LAYER_ID, this.id])
    let lastOwnIndex = -1
    styleLayers.forEach((styleLayer, index) => {
      if (ownIds.has(styleLayer.id)) lastOwnIndex = index
    })
    if (lastOwnIndex === -1 || lastOwnIndex + 1 >= styleLayers.length)
      return null
    return styleLayers[lastOwnIndex + 1].id
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
        paint: {
          ...heatmapPaint(),
          // A linear weight over cell counts clamps at count 5 and flattens
          // the map — scale logarithmically: 0.2 + 0.8·ln(count)/ln(5000)
          // (a single point = the classic 0.2, ~5000 points saturate at 1).
          "heatmap-weight": [
            "min",
            1,
            ["+", 0.2, ["*", 0.094, ["ln", ["coalesce", ["get", "count"], 1]]]],
          ],
        },
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
          "circle-stroke-color": getMarkerStrokeColor(this.styleName),
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
    const beforeId = this._layerAbove()
    this.remove()
    this.startAt = nextStartAt
    this.endAt = nextEndAt
    this.add(options, beforeId)
    this.setVisibility(wasVisible)
  }

  _buildTileUrl(startAt = this.startAt, endAt = this.endAt) {
    const params = new URLSearchParams()

    if (startAt) params.set("start_at", startAt)
    if (endAt) params.set("end_at", endAt)
    // Never the raw api key: the Bearer header authenticates (transformRequest)
    if (this.apiKey) params.set("u", cachePartitioner(this.apiKey))
    if (this._cacheBuster) params.set("_", String(this._cacheBuster))

    const query = params.toString()
    const path = "/api/v1/tiles/points/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }
}
