import {
  drawPointHoles,
  drawHexagonHoles,
  attachTiledHandlers,
  detachTiledHandlers,
  resizeCanvas,
  metersPerPixel,
} from "./fog_render.js"
import { FogHexagonSource } from "./fog_hexagon_source.js"

const ZOOM_DEBOUNCE_MS = 250

export class FogLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = "fog"
    this.visible = options.visible !== undefined ? options.visible : false
    this.canvas = null
    this.ctx = null
    this.clearRadius = options.clearRadius || 1000
    this.mode = options.mode === "hexagons" ? "hexagons" : "points"
    this.reader = options.reader
    this.getRange = options.getRange
    this.timers = options.timers ?? globalThis
    this.document = options.document ?? globalThis.document
    this.onError = options.onError
    this.destroyed = false
    this.points = []
    this.data = null
    this.hexBoundaries = []
    this.hexSource = options.hexSource ?? new FogHexagonSource()
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
      if (this._zoomDebounceTimer)
        this.timers.clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = this.timers.setTimeout(() => {
        this._zoomDebounceTimer = null
        this._handleZoomEnd()
      }, ZOOM_DEBOUNCE_MS)
    }
  }

  add(data) {
    if (this.destroyed) return
    this.data = data
    this.points = data.features || []
    this.createCanvas()
    if (this.visible) {
      this.show()
    }
    this.render()
  }

  update(data) {
    this.data = data
    if (this.tiledSource) {
      this._refreshTiledPositions()
      return
    }
    this.points = data.features || []
    this.render()
  }
  setTiledSource(enabled) {
    const next = enabled === true
    if (next === this.tiledSource) return

    this.tiledSource = next
    this._detachTiledHandlers()
    if (next) {
      if (this.canvas && this.visible) {
        this._attachTiledHandlers()
        this._refreshTiledPositions()
      }
    } else {
      this.points = this.data?.features || []
      this.render()
    }
  }

  createCanvas() {
    if (this.canvas) return
    this.canvas = this.document.createElement("canvas")
    this.canvas.className = "fog-canvas"
    this.canvas.style.position = "absolute"
    this.canvas.style.top = "0"
    this.canvas.style.left = "0"
    this.canvas.style.pointerEvents = "none"
    this.canvas.style.zIndex = "10"
    this.canvas.style.display = this.visible ? "block" : "none"

    this.ctx = this.canvas.getContext("2d")
    const mapContainer = this.map.getContainer()
    mapContainer.appendChild(this.canvas)
    this._renderHandler = () => this.render()
    this._resizeHandler = () => this.resizeCanvas()
    this.map.on("move", this._renderHandler)
    this.map.on("zoom", this._renderHandler)
    this.map.on("resize", this._resizeHandler)
    this.map.on("zoomend", this._zoomEndHandler)

    if (this.tiledSource && this.visible) {
      this._attachTiledHandlers()
    }

    this.resizeCanvas()
  }
  _attachTiledHandlers() {
    attachTiledHandlers(this)
  }
  _detachTiledHandlers() {
    detachTiledHandlers(this)
  }

  _scheduleTiledRefresh() {
    if (this._tiledRefreshTimer)
      this.timers.clearTimeout(this._tiledRefreshTimer)
    this._tiledRefreshTimer = this.timers.setTimeout(() => {
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
    if (
      features.length === 0 &&
      this.points.length > 0 &&
      this.map.isSourceLoaded?.(this.tiledSourceId) === false
    )
      return

    this.points = features
    this.render()
  }

  resizeCanvas() {
    resizeCanvas(this)
  }

  render() {
    if (!this.canvas || !this.ctx || !this.visible) return

    const { width, height } = this.canvas
    this.ctx.clearRect(0, 0, width, height)
    this.ctx.fillStyle = "rgba(0, 0, 0, 0.6)"
    this.ctx.fillRect(0, 0, width, height)

    this.ctx.globalCompositeOperation = "destination-out"
    this.ctx.fillStyle = "rgba(0, 0, 0, 1)"

    if (this.mode === "hexagons") {
      drawHexagonHoles(this)
    } else {
      drawPointHoles(this)
    }

    this.ctx.globalCompositeOperation = "source-over"
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
    if (this.destroyed || !this.reader || !this.getRange) return

    const start = this.getRange().startAt
    const end = this.getRange().endAt
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
      await this.hexSource.load(this.reader, { start_at: start, end_at: end })
      if (this.destroyed || this._hexFetchKey !== key) return
      this.hexBoundaries = this.hexSource.boundariesFor(this.map.getZoom())
      this.render()
    } catch (error) {
      if (error.name !== "AbortError" && !this.destroyed)
        this.onError?.("fog_load_failed")
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
    return metersPerPixel(this, latitude)
  }

  show() {
    this.visible = true
    if (this.canvas) {
      this.canvas.style.display = "block"
      this.render()
    }
    if (this.tiledSource) {
      if (this.canvas) this._attachTiledHandlers()
      this._refreshTiledPositions()
    }
    if (this.mode === "hexagons") {
      this._ensureHexagons()
    }
  }

  hide() {
    this.hexSource.cancel()
    this._hexFetchKey = null
    this.visible = false
    if (this.canvas) {
      this.canvas.style.display = "none"
    }
    this._detachTiledHandlers()
  }

  toggle(visible = !this.visible) {
    if (visible) {
      this.show()
    } else {
      this.hide()
    }
  }

  remove() {
    this.destroyed = true
    this.hexSource.destroy()
    this._hexFetchKey = null
    this.points = []
    this.hexBoundaries = []
    if (this.canvas) {
      this.canvas.remove()
      this.canvas = null
      this.ctx = null
    }
    if (this._renderHandler) {
      this.map.off("move", this._renderHandler)
      this.map.off("zoom", this._renderHandler)
      this._renderHandler = null
    }
    if (this._resizeHandler) {
      this.map.off("resize", this._resizeHandler)
      this._resizeHandler = null
    }
    this._detachTiledHandlers()
    this.map.off("zoomend", this._zoomEndHandler)
    if (this._zoomDebounceTimer) {
      this.timers.clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = null
    }
  }
}
