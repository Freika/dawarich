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

    // Update on map move/zoom/resize
    this.map.on("move", () => this.render())
    this.map.on("zoom", () => this.render())
    this.map.on("resize", () => this.resizeCanvas())
    this.map.on("zoomend", this._zoomEndHandler)

    this.resizeCanvas()
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
    this.points.forEach((feature) => {
      const coords = feature.geometry.coordinates
      const point = this.map.project(coords)

      // Calculate pixel radius based on zoom level
      const metersPerPixel = this.getMetersPerPixel(coords[1])
      const radiusPixels = this.clearRadius / metersPerPixel

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

    // Remove event listeners
    this.map.off("move", this.render)
    this.map.off("zoom", this.render)
    this.map.off("resize", this.resizeCanvas)
    this.map.off("zoomend", this._zoomEndHandler)
    if (this._zoomDebounceTimer) {
      clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = null
    }
  }
}
