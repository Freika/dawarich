import { VectorTileLayer } from "./vector_tile_layer"

/**
 * Vector-tile line layer for canonical backend Tracks.
 */
export class TracksMvtLayer extends VectorTileLayer {
  constructor(map, options = {}) {
    const tracksEnabled = options.tracksEnabled === true
    super(map, {
      id: "tracks-mvt",
      ...options,
      visible: tracksEnabled,
    })
    this.tileKind = "tracks"
    this.flightBounds = ["start_timestamp", "end_timestamp"]
    this.tracksEnabled = tracksEnabled
    this.trackColor = options.trackColor || "#6366F1"
    this.speedColoring = options.speedColoring === true
    this.speedColorScale = options.speedColorScale
    this.onEmptyTracks = options.onEmptyTracks || null
    this._sourceDataHandler = null
    this._emptyTracksReported = false
  }

  add(data, beforeId = null) {
    super.add(data, beforeId)
    this._emptyTracksReported = false
    this._watchEmptyTracks()
  }

  remove() {
    this._unwatchEmptyTracks()
    super.remove()
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

    this._rebuild({ startAt: this.startAt, endAt: this.endAt })
  }

  _appendTileParams(params) {
    if (this.speedColoring) params.set("speed_coloring", "true")
  }
}
