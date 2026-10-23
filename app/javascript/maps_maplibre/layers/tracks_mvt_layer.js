import { bumpTileVersion } from "maps_maplibre/utils/tile_freshness"
import { BaseLayer, isAbortedRequest } from "./base_layer"

// FNV-1a over the api key: a non-secret cache partitioner keying URL-based
// caches per user — auth itself travels only in the Authorization header
// (map-level transformRequest covers every /api/v1/tiles/ path).
function trackCachePartitioner(value) {
  let hash = 0x811c9dc5
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return (hash >>> 0).toString(16)
}

/**
 * Vector-tile line layer for canonical backend Tracks.
 */
export class TracksMvtLayer extends BaseLayer {
  constructor(map, options = {}) {
    const tracksEnabled = options.tracksEnabled === true
    super(map, {
      id: "tracks-mvt",
      ...options,
      visible: tracksEnabled,
    })
    this.tracksEnabled = tracksEnabled
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.apiKey = options.apiKey || null
    this.importId = options.importId || null
    this.trackColor = options.trackColor || "#6366F1"
    this.speedColoring = options.speedColoring === true
    this.speedColorScale = options.speedColorScale
    this.onTileError = options.onTileError || null
    this.onEmptyTracks = options.onEmptyTracks || null
    this._tileUrl = null
    this._tileErrorHandler = null
    this._tileErrorReported = false
    this._sourceDataHandler = null
    this._emptyTracksReported = false
    this.flightWindows = []
  }

  add(data, beforeId = null) {
    super.add(data, beforeId)
    if (this.flightWindows.length) this._applyFlightFilter()
    this._tileErrorReported = false
    this._watchTileErrors()
    this._emptyTracksReported = false
    this._watchEmptyTracks()
  }

  remove() {
    this._unwatchTileErrors()
    this._unwatchEmptyTracks()
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

  _watchEmptyTracks() {
    if (this._sourceDataHandler || !this.onEmptyTracks) return

    this._sourceDataHandler = (event) => {
      if (event?.sourceId !== this.sourceId || !event?.isSourceLoaded) return
      if (this._emptyTracksReported || !this.tracksEnabled) return

      const features =
        this.map.querySourceFeatures?.(this.sourceId, {
          sourceLayer: "tracks",
        }) ?? []
      if (features.length > 0) {
        this._unwatchEmptyTracks()
        return
      }

      this._emptyTracksReported = true
      this.onEmptyTracks()
    }
    this.map.on("sourcedata", this._sourceDataHandler)
  }

  _unwatchEmptyTracks() {
    if (!this._sourceDataHandler) return

    this.map.off("sourcedata", this._sourceDataHandler)
    this._sourceDataHandler = null
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
        type: "line",
        source: this.sourceId,
        "source-layer": "tracks",
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": this._lineColor(),
          "line-width": 3,
          "line-opacity": 1,
        },
      },
    ]
  }

  setEnabled(enabled) {
    this.tracksEnabled = enabled === true
    this.toggle(this.tracksEnabled)
  }

  setFlightWindows(windows = []) {
    this.flightWindows = windows
    this._applyFlightFilter()
  }

  _applyFlightFilter() {
    const masked = this.flightWindows.map(([start, end]) => [
      "all",
      [">=", ["get", "start_timestamp"], start],
      ["<=", ["get", "end_timestamp"], end],
    ])
    if (this.map.getLayer(this.id)) {
      this.map.setFilter(
        this.id,
        masked.length ? ["!", ["any", ...masked]] : null,
      )
    }
  }

  setColors({ trackColor } = {}) {
    if (trackColor) this.trackColor = trackColor
    this._repaint()
  }

  _repaint() {
    if (!this.map.getLayer(this.id)) return
    this.map.setPaintProperty(this.id, "line-color", this._lineColor())
  }

  _lineColor() {
    if (!this.speedColoring) return this.trackColor

    const defaults = "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300"
    const parse = (scale) => {
      const stops = new Map()
      for (const segment of String(scale).split("|")) {
        const [speed, color, extra] = segment.split(":")
        const value = Number(speed)
        if (
          !speed?.trim() ||
          !Number.isFinite(value) ||
          value < 0 ||
          !/^#[0-9a-f]{6}$/i.test(color) ||
          extra !== undefined
        )
          return []
        stops.set(value, color)
      }
      return [...stops].sort(([a], [b]) => a - b)
    }
    let stops = parse(this.speedColorScale)
    if (stops.length < 2) stops = parse(defaults)
    return [
      "interpolate",
      ["linear"],
      [
        "to-number",
        ["coalesce", ["get", "segment_speed"], ["get", "avg_speed"]],
        0,
      ],
      ...stops.flatMap(([speed, color]) => [speed, ["to-color", color]]),
    ]
  }

  setSpeedColoring({ enabled, scale } = {}) {
    const changed = this.speedColoring !== (enabled === true)
    this.speedColoring = enabled === true
    this.speedColorScale = scale
    if (!changed) {
      this._repaint()
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
    let ownIndex = -1
    styleLayers.forEach((styleLayer, index) => {
      if (styleLayer.id === this.id) ownIndex = index
    })
    if (ownIndex === -1 || ownIndex + 1 >= styleLayers.length) return null
    return styleLayers[ownIndex + 1].id
  }

  refresh() {
    bumpTileVersion("/api/v1/tiles/tracks/")
    if (this.map.refreshTiles && this.map.getSource(this.sourceId)) {
      this.map.refreshTiles(this.sourceId)
      return
    }

    const wasVisible = this.visible
    const beforeId = this._layerAbove()
    this.remove()
    this.add({ startAt: this.startAt, endAt: this.endAt }, beforeId)
    this.setVisibility(wasVisible)
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
    if (this.speedColoring) params.set("speed_coloring", "true")
    // Never the raw api key: the Bearer header authenticates (transformRequest)
    if (this.apiKey) params.set("u", trackCachePartitioner(this.apiKey))

    const query = params.toString()
    const path = "/api/v1/tiles/tracks/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }
}
