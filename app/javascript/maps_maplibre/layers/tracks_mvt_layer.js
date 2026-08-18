import { BaseLayer } from "./base_layer"

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

// Decodes the user's "0:#00ff00|15:#00ffff|..." speed scale. Returns sorted
// [speed, color] stops, or null when the setting is absent or malformed.
export function parseSpeedColorScale(encoded) {
  if (!encoded || typeof encoded !== "string") return null

  const stops = encoded
    .split("|")
    .map((entry) => entry.split(":"))
    .filter(
      ([speed, color]) =>
        speed !== undefined &&
        color !== undefined &&
        Number.isFinite(Number(speed)) &&
        /^#[0-9a-fA-F]{6}$/.test(color),
    )
    .map(([speed, color]) => [Number(speed), color])
    .sort((a, b) => a[0] - b[0])

  return stops.length >= 2 ? stops : null
}

// Matches classic speed coloring's clamp (speed_colors.js MAX_SPEED) so
// flights don't pin the top stop.
const MAX_SPEED_KMH = 150

/**
 * Vector-tile line layer serving BOTH the Tracks and Routes toggles under
 * tiled mode. Coloring is per-track (avg_speed / flat), an approximation of
 * classic per-vertex speed gradients — disclosed in the settings copy.
 */
export class TracksMvtLayer extends BaseLayer {
  constructor(map, options = {}) {
    const tracksEnabled = options.tracksEnabled === true
    const routesVisible = options.routesVisible === true
    super(map, {
      id: "tracks-mvt",
      ...options,
      visible: tracksEnabled || routesVisible,
    })
    this.tracksEnabled = tracksEnabled
    this.routesVisible = routesVisible
    this.startAt = options.startAt || null
    this.endAt = options.endAt || null
    this.apiKey = options.apiKey || null
    this.trackColor = options.trackColor || "#6366F1"
    this.routeColor = options.routeColor || "#0000ff"
    this.routeOpacity = options.routeOpacity ?? 1
    this.speedColoredRoutes = options.speedColoredRoutes === true
    this.speedColorScale = options.speedColorScale || null
    this.onTileError = options.onTileError || null
    this.onEmptyTracks = options.onEmptyTracks || null
    this._tileUrl = null
    this._cacheBuster = 0
    this._tileErrorHandler = null
    this._tileErrorReported = false
    this._sourceDataHandler = null
    this._emptyTracksReported = false
  }

  add(data, beforeId = null) {
    super.add(data, beforeId)
    this._tileErrorReported = false
    this._watchTileErrors()
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

  // Routes-on-tracks renders nothing for an account whose tracks were never
  // generated (throttled cloud backfill, fresh import) — without this note the
  // user sees Routes toggled on over an empty map and reads it as a bug.
  _watchEmptyTracks() {
    if (this._sourceDataHandler || !this.onEmptyTracks) return

    this._sourceDataHandler = (event) => {
      if (event?.sourceId !== this.sourceId || !event?.isSourceLoaded) return
      if (this._emptyTracksReported || !this.routesVisible) return

      const features =
        this.map.querySourceFeatures?.(this.sourceId, {
          sourceLayer: "tracks",
        }) ?? []
      if (features.length > 0) return

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
          "line-opacity": this._lineOpacity(),
        },
      },
    ]
  }

  // Color precedence: speed scale (approximate, per-track) > the user's route
  // color when only Routes drives the layer > the track color.
  _lineColor() {
    if (this.speedColoredRoutes) {
      const stops = parseSpeedColorScale(this.speedColorScale)
      if (stops) {
        const expression = [
          "interpolate",
          ["linear"],
          ["min", MAX_SPEED_KMH, ["coalesce", ["get", "avg_speed"], 0]],
        ]
        for (const [speed, color] of stops) expression.push(speed, color)
        return expression
      }
    }
    if (this._routesOnly()) return this.routeColor
    return this.trackColor
  }

  _lineOpacity() {
    return this._routesOnly() ? this.routeOpacity : 1
  }

  _routesOnly() {
    return this.routesVisible && !this.tracksEnabled
  }

  setModes({ tracksEnabled, routesVisible }) {
    if (tracksEnabled !== undefined) this.tracksEnabled = tracksEnabled
    if (routesVisible !== undefined) this.routesVisible = routesVisible
    this.setVisibility(this.tracksEnabled || this.routesVisible)
    this._repaint()
  }

  setRouteOpacity(opacity) {
    this.routeOpacity = opacity
    if (!this.map.getLayer(this.id)) return
    this.map.setPaintProperty(this.id, "line-opacity", this._lineOpacity())
  }

  setSpeedColoring(enabled, scale = this.speedColorScale) {
    this.speedColoredRoutes = enabled === true
    this.speedColorScale = scale
    this._repaint()
  }

  _repaint() {
    if (!this.map.getLayer(this.id)) return
    this.map.setPaintProperty(this.id, "line-color", this._lineColor())
    this.map.setPaintProperty(this.id, "line-opacity", this._lineOpacity())
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

  _layerAbove() {
    const styleLayers = this.map.getStyle?.()?.layers ?? []
    let ownIndex = -1
    styleLayers.forEach((styleLayer, index) => {
      if (styleLayer.id === this.id) ownIndex = index
    })
    if (ownIndex === -1 || ownIndex + 1 >= styleLayers.length) return null
    return styleLayers[ownIndex + 1].id
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
    this._emptyTracksReported = false
    this.add(options, beforeId)
    this.setVisibility(wasVisible)
  }

  _buildTileUrl(startAt = this.startAt, endAt = this.endAt) {
    const params = new URLSearchParams()

    if (startAt) params.set("start_at", startAt)
    if (endAt) params.set("end_at", endAt)
    // Never the raw api key: the Bearer header authenticates (transformRequest)
    if (this.apiKey) params.set("u", trackCachePartitioner(this.apiKey))
    if (this._cacheBuster) params.set("_", String(this._cacheBuster))

    const query = params.toString()
    const path = "/api/v1/tiles/tracks/{z}/{x}/{y}.mvt"

    return query ? `${path}?${query}` : path
  }
}
