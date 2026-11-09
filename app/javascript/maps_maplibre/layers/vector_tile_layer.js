import { bumpTileVersion } from "maps_maplibre/utils/tile_freshness"
import { BaseLayer, isAbortedRequest } from "./base_layer"

// FNV-1a over the api key: a non-secret cache partitioner keying URL-based
// caches per user — auth itself travels only in the Authorization header
// (map-level transformRequest covers every /api/v1/tiles/ path).
function cachePartitioner(value) {
  let hash = 0x811c9dc5
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return (hash >>> 0).toString(16)
}

/**
 * A layer drawn from vector tiles. Subclasses name their tile endpoint with
 * `tileKind` and the feature properties that bound a flight with
 * `flightBounds`.
 */
export class VectorTileLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, options)
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.apiKey = options.apiKey || null
    this.importId = options.importId || null
    this.onTileError = options.onTileError || null
    this.flightWindows = []
    this._tileUrl = null
    this._tileErrorHandler = null
    this._tileErrorReported = false
  }

  add(data, beforeId = null) {
    super.add(data, beforeId)
    if (this.flightWindows.length) this._applyFlightFilter()
    this._tileErrorReported = false
    this._watchTileErrors()
  }

  remove() {
    this._unwatchTileErrors()
    super.remove()
  }

  // A failed tile fetch (timeout, throttle, expired session) reaches the page
  // only as a map `error` event. Unwatched, the layer renders nothing and the
  // user sees an empty map with no explanation.
  _watchTileErrors() {
    if (this._tileErrorHandler || !this.onTileError) return

    this._tileErrorHandler = (event) => {
      if (event?.sourceId !== this.sourceId) return
      if (!this._isTileFailure(event)) return
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

  _isTileFailure(event) {
    return !isAbortedRequest(event.error)
  }

  setFlightWindows(windows = []) {
    this.flightWindows = windows
    this._applyFlightFilter()
  }

  _applyFlightFilter() {
    const [startProperty, endProperty] = this.flightBounds
    const masked = this.flightWindows.map(([start, end]) => [
      "all",
      [">=", ["get", startProperty], start],
      // An aggregate is hidden only if every constituent feature is in the window.
      ["<=", ["get", endProperty], end],
    ])
    const filter = masked.length ? ["!", ["any", ...masked]] : null
    for (const layerId of this.getLayerIds()) {
      if (this.map.getLayer(layerId)) this.map.setFilter(layerId, filter)
    }
  }

  refresh() {
    bumpTileVersion(`/api/v1/tiles/${this.tileKind}/`)
    if (this.map.refreshTiles && this.map.getSource(this.sourceId)) {
      this.map.refreshTiles(this.sourceId)
      return
    }

    this._rebuild({ startAt: this.startAt, endAt: this.endAt })
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

    this._rebuild(options, () => {
      this.startAt = nextStartAt
      this.endAt = nextEndAt
    })
  }

  _rebuild(data, whileRemoved = () => {}) {
    const wasVisible = this.visible
    const beforeId = this._layerAbove()
    this.remove()
    whileRemoved()
    this.add(data, beforeId)
    this.setVisibility(wasVisible)
  }

  // The id of the layer stacked directly above this one, so a remove+add
  // cycle can put the sub-layers back where they were instead of on top.
  _layerAbove() {
    const styleLayers = this.map.getStyle?.()?.layers ?? []
    const ownIds = new Set(this.getLayerIds())
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

  _buildTileUrl(startAt = this.startAt, endAt = this.endAt) {
    const params = new URLSearchParams()

    if (startAt) params.set("start_at", startAt)
    if (endAt) params.set("end_at", endAt)
    if (this.importId) params.set("import_id", this.importId)
    this._appendTileParams(params)
    // Never the raw api key: the Bearer header authenticates (transformRequest)
    if (this.apiKey) params.set("u", cachePartitioner(this.apiKey))

    const query = params.toString()
    const path = `/api/v1/tiles/${this.tileKind}/{z}/{x}/{y}.mvt`

    return query ? `${path}?${query}` : path
  }

  _appendTileParams(_params) {}
}
