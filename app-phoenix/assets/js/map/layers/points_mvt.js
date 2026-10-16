import { getMarkerStrokeColor } from "../algorithms/marker_theme.js"
import { BaseLayer, isAbortedRequest } from "./base.js"
import { heatmapPaint } from "./heatmap.js"
import { queueTileRefresh, retryTileSource } from "./tile_refresh.js"

export class PointsMvtLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "points-mvt", ...options })
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.freshness = options.freshness
    this.importId = options.importId || null
    this.styleName = options.styleName
    this._tileUrl = null
    this.heatmapVisible = options.heatmapVisible === true
    this.onTileError = options.onTileError || null
    this._tileErrorHandler = null
    this._tileErrorReported = false
    this.flightWindows = []
    this._visibleCirclePaint = {
      "circle-opacity": 1,
      "circle-stroke-opacity": 1,
    }
  }
  add(data, beforeId = null) {
    super.add(data, beforeId)
    for (const [property, value] of Object.entries(this._visibleCirclePaint)) {
      this.setCircleOpacity(property, value)
    }
    if (this.flightWindows.length) this._applyFlightFilter()
    this._tileErrorReported = false
    this._watchTileErrors()
  }

  remove() {
    this._cancelTileRefresh?.()
    this._cancelTileRefresh = null
    this._unwatchTileErrors()
    super.remove()
  }

  _watchTileErrors() {
    if (this._tileErrorHandler || !this.onTileError) return

    this._tileErrorHandler = (event) => {
      if (event?.sourceId !== this.sourceId) return
      if (isAbortedRequest(event.error)) return
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

  static CIRCLE_RADIUS = 6

  static CIRCLE_STROKE_WIDTH = 2

  setHeatmapVisible(visible) {
    this.heatmapVisible = visible
    this._applyLayerVisibility(PointsMvtLayer.HEATMAP_LAYER_ID, visible)
  }

  setFlightWindows(windows = []) {
    this.flightWindows = windows
    this._applyFlightFilter()
  }

  _applyFlightFilter() {
    const masked = this.flightWindows.map(([start, end]) => [
      "all",
      [">=", ["get", "timestamp"], start],
      ["<=", ["get", "max_timestamp"], end],
    ])
    const filter = masked.length ? ["!", ["any", ...masked]] : null
    if (this.map.getLayer(this.id)) this.map.setFilter(this.id, filter)
    if (this.map.getLayer(PointsMvtLayer.HEATMAP_LAYER_ID)) {
      this.map.setFilter(PointsMvtLayer.HEATMAP_LAYER_ID, filter)
    }
  }
  get anyVisible() {
    return Boolean(this.visible || this.heatmapVisible)
  }
  setVisibility(visible) {
    this.visible = visible
    this._applyLayerVisibility(this.id, visible)
    this._applyLayerVisibility(
      PointsMvtLayer.HEATMAP_LAYER_ID,
      this.heatmapVisible,
    )
  }
  setSourceKeepAlive(keepAlive) {
    this.sourceKeepAlive = keepAlive === true
    this.setVisibility(this.visible)
  }

  setCircleOpacity(property, value) {
    this._visibleCirclePaint[property] = value
    if (!this._paintHidden && this.map.getLayer(this.id)) {
      this.map.setPaintProperty?.(this.id, property, value)
    }
  }

  _applyLayerVisibility(layerId, visible) {
    if (!this.map.getLayer(layerId)) return

    if (layerId === this.id && !visible && this.sourceKeepAlive) {
      this.map.setLayoutProperty(layerId, "visibility", "visible")
      this.map.setPaintProperty?.(layerId, "circle-opacity", 0)
      this.map.setPaintProperty?.(layerId, "circle-stroke-opacity", 0)
      this.map.setPaintProperty?.(layerId, "circle-radius", 0)
      this.map.setPaintProperty?.(layerId, "circle-stroke-width", 0)
      this._paintHidden = true
      return
    }
    if (layerId === this.id && this._paintHidden) {
      for (const [property, value] of Object.entries(
        this._visibleCirclePaint,
      )) {
        this.map.setPaintProperty?.(layerId, property, value)
      }
      this.map.setPaintProperty?.(
        layerId,
        "circle-radius",
        PointsMvtLayer.CIRCLE_RADIUS,
      )
      this.map.setPaintProperty?.(
        layerId,
        "circle-stroke-width",
        PointsMvtLayer.CIRCLE_STROKE_WIDTH,
      )
      this._paintHidden = false
    }

    this.map.setLayoutProperty(
      layerId,
      "visibility",
      visible ? "visible" : "none",
    )
  }

  retry() {
    retryTileSource(this, "points")
  }

  refresh() {
    this.freshness?.bump("points")
    if (this.map.refreshTiles && this.map.getSource(this.sourceId)) {
      this._cancelTileRefresh?.()
      this._cancelTileRefresh = queueTileRefresh(this.map, this.sourceId)
      return
    }

    const wasVisible = this.visible
    const beforeId = this._layerAbove()
    this.remove()
    this.add({ startAt: this.startAt, endAt: this.endAt }, beforeId)
    this.setVisibility(wasVisible)
  }
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
          "circle-radius": PointsMvtLayer.CIRCLE_RADIUS,
          "circle-stroke-width": PointsMvtLayer.CIRCLE_STROKE_WIDTH,
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
    if (this.importId) params.set("import_id", this.importId)

    const query = params.toString()
    const path = "/native/map/data/tiles/points/{z}/{x}/{y}"

    return query ? `${path}?${query}` : path
  }
}
