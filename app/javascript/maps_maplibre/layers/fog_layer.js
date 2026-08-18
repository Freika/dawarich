import { FogHexagonSource } from "./fog_hexagon_source"

/**
 * Fog of war layer
 * Shows explored vs unexplored areas using canvas overlay
 * Does not extend BaseLayer as it uses canvas instead of MapLibre layers
 */
const ZOOM_DEBOUNCE_MS = 250

export class FogLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = "fog"
    this.visible = options.visible !== undefined ? options.visible : false
    this.canvas = null
    this.ctx = null
    this.clearRadius = options.clearRadius || 1000 // meters
    this.mode = options.mode === "hexagons" ? "hexagons" : "points"
    this.api = options.api || null
    this.controller = options.controller || null
    this.points = []
    this.data = null // Store original data for updates
    this.hexBoundaries = []
    this.hexSource = new FogHexagonSource()
    // Tiled mode: holes come from the points MVT source instead of a bulk
    // GeoJSON — queried on settled events only (render stays a pure draw).
    this.tiledSource = options.tiledSource === true
    this.tiledSourceId = options.tiledSourceId || "points-mvt-source"
    this._tiledRefreshTimer = null
    this._tiledRefreshHandler = null
    this._sourceDataHandler = null
    this._renderHandler = null
    this._resizeHandler = null
    this._hexFetchKey = null
    this._hexFetchPromise = null
    this._zoomDebounceTimer = null
    this._zoomEndHandler = () => {
      if (this._zoomDebounceTimer) clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = setTimeout(() => {
        this._zoomDebounceTimer = null
        this._handleZoomEnd()
      }, ZOOM_DEBOUNCE_MS)
    }
  }

  add(data) {
    this.data = data // Store for later updates
    this.points = data.features || []
    this.createCanvas()
    if (this.visible) {
      this.show()
    }
    this.render()
  }

  update(data) {
    this.data = data // Store for later updates
    this.points = data.features || []
    this.render()
  }

  createCanvas() {
    if (this.canvas) return

    // Create canvas overlay
    this.canvas = document.createElement("canvas")
    this.canvas.className = "fog-canvas"
    this.canvas.style.position = "absolute"
    this.canvas.style.top = "0"
    this.canvas.style.left = "0"
    this.canvas.style.pointerEvents = "none"
    this.canvas.style.zIndex = "10"
    this.canvas.style.display = this.visible ? "block" : "none"

    this.ctx = this.canvas.getContext("2d")

    // Add to map container
    const mapContainer = this.map.getContainer()
    mapContainer.appendChild(this.canvas)

    // Update on map move/zoom/resize. Handlers are stored on `this` so
    // remove() can actually detach them — an off() with a fresh arrow is a
    // silent no-op that leaks a render loop per style change.
    this._renderHandler = () => this.render()
    this._resizeHandler = () => this.resizeCanvas()
    this.map.on("move", this._renderHandler)
    this.map.on("zoom", this._renderHandler)
    this.map.on("resize", this._resizeHandler)
    this.map.on("zoomend", this._zoomEndHandler)

    if (this.tiledSource) {
      // querySourceFeatures re-walks every loaded tile — far too heavy for the
      // per-frame move/zoom path. Refresh the cached hole set only when the
      // map settles or new tiles land, debounced; render() just draws it.
      this._tiledRefreshHandler = () => this._scheduleTiledRefresh()
      this._sourceDataHandler = (event) => {
        if (event?.sourceId !== this.tiledSourceId) return
        this._scheduleTiledRefresh()
      }
      this.map.on("moveend", this._tiledRefreshHandler)
      this.map.on("zoomend", this._tiledRefreshHandler)
      this.map.on("sourcedata", this._sourceDataHandler)
    }

    this.resizeCanvas()
  }

  _scheduleTiledRefresh() {
    if (this._tiledRefreshTimer) clearTimeout(this._tiledRefreshTimer)
    this._tiledRefreshTimer = setTimeout(() => {
      this._tiledRefreshTimer = null
      this._refreshTiledPositions()
    }, ZOOM_DEBOUNCE_MS)
  }

  _refreshTiledPositions() {
    if (!this.tiledSource) return

    const features =
      this.map.querySourceFeatures?.(this.tiledSourceId, {
        sourceLayer: "points",
      }) ?? []
    // During zoom transitions placeholder tiles return nothing — keep the
    // previous hole set rather than flashing the cleared area back to black.
    if (features.length === 0 && this.points.length > 0) return

    this.points = features
    this.render()
  }

  resizeCanvas() {
    if (!this.canvas) return

    const container = this.map.getContainer()
    this.canvas.width = container.offsetWidth
    this.canvas.height = container.offsetHeight
    this.render()
  }

  render() {
    if (!this.canvas || !this.ctx || !this.visible) return

    const { width, height } = this.canvas

    // Clear canvas
    this.ctx.clearRect(0, 0, width, height)

    // Draw fog overlay
    this.ctx.fillStyle = "rgba(0, 0, 0, 0.6)"
    this.ctx.fillRect(0, 0, width, height)

    this.ctx.globalCompositeOperation = "destination-out"
    this.ctx.fillStyle = "rgba(0, 0, 0, 1)" // Fully opaque to completely clear fog

    if (this.mode === "hexagons") {
      this.renderHexagonHoles()
    } else {
      this.renderPointHoles()
    }

    this.ctx.globalCompositeOperation = "source-over"
  }

  renderPointHoles() {
    // Tiled features are decimation-cell centroids spaced grid_px display
    // pixels apart — a hole radius below that spacing renders a travelled
    // corridor as dots, so clamp to the cell spacing (4px below z14).
    const minRadius = this.tiledSource ? (this.map.getZoom() < 14 ? 4 : 1) : 0

    this.points.forEach((feature) => {
      const coords = feature.geometry.coordinates
      const point = this.map.project(coords)

      // Calculate pixel radius based on zoom level
      const metersPerPixel = this.getMetersPerPixel(coords[1])
      const radiusPixels = Math.max(
        this.clearRadius / metersPerPixel,
        minRadius,
      )

      this.ctx.beginPath()
      this.ctx.arc(point.x, point.y, radiusPixels, 0, Math.PI * 2)
      this.ctx.fill()
    })
  }

  renderHexagonHoles() {
    const bounds = this.map.getBounds()
    const west = bounds.getWest()
    const east = bounds.getEast()
    const south = bounds.getSouth()
    const north = bounds.getNorth()

    this.ctx.strokeStyle = "rgba(0, 0, 0, 1)"
    this.ctx.lineWidth = 1.5

    for (const hex of this.hexBoundaries) {
      if (
        hex.maxLng < west ||
        hex.minLng > east ||
        hex.maxLat < south ||
        hex.minLat > north
      ) {
        continue
      }

      this.ctx.beginPath()
      hex.coords.forEach(([lng, lat], i) => {
        const point = this.map.project([lng, lat])
        if (i === 0) {
          this.ctx.moveTo(point.x, point.y)
        } else {
          this.ctx.lineTo(point.x, point.y)
        }
      })
      this.ctx.closePath()
      this.ctx.fill()
      this.ctx.stroke()
    }
  }

  setMode(mode) {
    const newMode = mode === "hexagons" ? "hexagons" : "points"
    if (newMode === this.mode) return
    this.mode = newMode

    if (this.mode === "hexagons" && this.visible) {
      this._ensureHexagons()
    } else {
      this.render()
    }
  }

  reloadHexagons() {
    if (this.visible && this.mode === "hexagons") {
      this._ensureHexagons()
    }
  }

  async _ensureHexagons() {
    if (!this.api || !this.controller) return

    const start = this.controller.startDateValue
    const end = this.controller.endDateValue
    const key = `${start}|${end}`

    if (this._hexFetchKey === key) {
      if (!this._hexFetchPromise) this.render()
      return this._hexFetchPromise
    }

    this._hexFetchKey = key
    const promise = this._fetchHexagons(start, end, key).finally(() => {
      if (this._hexFetchPromise === promise) this._hexFetchPromise = null
    })
    this._hexFetchPromise = promise
    return promise
  }

  async _fetchHexagons(start, end, key) {
    try {
      await this.hexSource.load(this.api, { start_at: start, end_at: end })
      if (this._hexFetchKey !== key) return
      this.hexBoundaries = this.hexSource.boundariesFor(this.map.getZoom())
      this.render()
    } catch (error) {
      console.error("[FogLayer] Failed to load fog hexagons:", error)
      if (this._hexFetchKey === key) this._hexFetchKey = null
    }
  }

  _handleZoomEnd() {
    if (!this.visible || this.mode !== "hexagons" || !this.hexSource.loaded) {
      return
    }
    if (!this.hexSource.resolutionChanged(this.map.getZoom())) return

    this.hexBoundaries = this.hexSource.boundariesFor(this.map.getZoom())
    this.render()
  }

  getMetersPerPixel(latitude) {
    const earthCircumference = 40075017 // meters at equator
    const latitudeRadians = (latitude * Math.PI) / 180
    const zoom = this.map.getZoom()
    return (earthCircumference * Math.cos(latitudeRadians)) / (256 * 2 ** zoom)
  }

  show() {
    this.visible = true
    if (this.canvas) {
      this.canvas.style.display = "block"
      this.render()
    }
    // Tiles may have loaded while fog was hidden — pick them up immediately.
    if (this.tiledSource) {
      this._refreshTiledPositions()
    }
    if (this.mode === "hexagons") {
      this._ensureHexagons()
    }
  }

  hide() {
    this.visible = false
    if (this.canvas) {
      this.canvas.style.display = "none"
    }
  }

  toggle(visible = !this.visible) {
    if (visible) {
      this.show()
    } else {
      this.hide()
    }
  }

  remove() {
    if (this.canvas) {
      this.canvas.remove()
      this.canvas = null
      this.ctx = null
    }

    // Remove event listeners via the stored references they were registered with
    if (this._renderHandler) {
      this.map.off("move", this._renderHandler)
      this.map.off("zoom", this._renderHandler)
      this._renderHandler = null
    }
    if (this._resizeHandler) {
      this.map.off("resize", this._resizeHandler)
      this._resizeHandler = null
    }
    if (this._tiledRefreshHandler) {
      this.map.off("moveend", this._tiledRefreshHandler)
      this.map.off("zoomend", this._tiledRefreshHandler)
      this._tiledRefreshHandler = null
    }
    if (this._sourceDataHandler) {
      this.map.off("sourcedata", this._sourceDataHandler)
      this._sourceDataHandler = null
    }
    if (this._tiledRefreshTimer) {
      clearTimeout(this._tiledRefreshTimer)
      this._tiledRefreshTimer = null
    }
    this.map.off("zoomend", this._zoomEndHandler)
    if (this._zoomDebounceTimer) {
      clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = null
    }
  }
}
