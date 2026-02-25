/**
 * Fog of war layer
 * Shows explored vs unexplored areas using canvas overlay
 * Does not extend BaseLayer as it uses canvas instead of MapLibre layers
 */
export class FogLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = "fog"
    this.visible = options.visible !== undefined ? options.visible : false
    this.canvas = null
    this.ctx = null
    this.clearRadius = options.clearRadius || 1000 // meters
    this.points = []
    this.data = null // Store original data for updates
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

    // Clear circles around visited points
    this.ctx.globalCompositeOperation = "destination-out"
    this.ctx.fillStyle = "rgba(0, 0, 0, 1)" // Fully opaque to completely clear fog

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

    this.ctx.globalCompositeOperation = "source-over"
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
  }
}
