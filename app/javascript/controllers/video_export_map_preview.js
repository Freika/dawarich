import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"
import {
  DEFAULT_MARKER_COLOR,
  DEFAULT_ROUTE_COLOR,
} from "./video_export_presets"
import {
  addArrowMarker,
  addDotLayers,
  addRouteLayers,
  buildGradient,
  extractCoordsFromGeoJSON,
  MARKER_GLOW_LAYER,
  MARKER_LAYER,
  ROUTE_LAYER,
} from "./video_export_preview_layers"
import { cumulativeDistance } from "./video_export_preview_math"
import { PreviewOverlays } from "./video_export_preview_overlays"
import {
  SAMPLE_ROUTE,
  SAMPLE_ROUTE_NAME,
} from "./video_export_preview_sample_route"

export class MapPreview {
  constructor(container, wrapperEl, apiKey) {
    this.container = container
    this.wrapperEl = wrapperEl
    this.apiKey = apiKey
    this.map = null
    this.coords = null
    this.bounds = null
    this.markerStyle = "dot"
    this.arrowMarker = null
    this.overlays = new PreviewOverlays(wrapperEl)
    this._routeColor = DEFAULT_ROUTE_COLOR
    this._routeWidth = 4
    this._markerColor = DEFAULT_MARKER_COLOR
    this._style = "dark"
    this._destroyed = false
  }

  async show(trackId, options = {}) {
    this._destroyed = false
    this._style = options.style || "dark"
    this._routeColor = options.routeColor || DEFAULT_ROUTE_COLOR
    this._routeWidth = options.routeWidth || 4
    this._markerColor = options.markerColor || DEFAULT_MARKER_COLOR
    this.markerStyle = options.markerStyle || "dot"

    this.coords = await this._loadCoords(trackId)
    if (!this.coords || this.coords.length < 2) this.coords = SAMPLE_ROUTE

    const style = await getMapStyle(this._style)

    // Wait for the browser to lay out the container (modal may have just opened)
    await new Promise((r) => requestAnimationFrame(r))

    if (this.map) {
      this.map.remove()
      this.map = null
    }

    this.map = new maplibregl.Map({
      container: this.container,
      style,
      interactive: false,
      attributionControl: false,
    })

    this.map.on("load", () => {
      this._initLayers()
      this._fitBounds()
      this.overlays.mount()
      this.overlays.updateTheme(this._style)
      if (options.layout) this.overlays.updateLayout(options.layout)
      if (options.overlays) this.overlays.updateVisibility(options.overlays)
      this.overlays.updateTrackName(
        options.trackName ||
          (this.coords === SAMPLE_ROUTE ? SAMPLE_ROUTE_NAME : ""),
      )
      this._updateOverlayStats()
    })
  }

  // -- Public update methods ------------------------------------------------

  updateStyle(styleName) {
    if (!this.map) return
    this._style = styleName
    this._reloadStyle()
  }

  updateRouteColor(color) {
    this._routeColor = color
    if (this.map?.getLayer(ROUTE_LAYER))
      this.map.setPaintProperty(
        ROUTE_LAYER,
        "line-gradient",
        buildGradient(color),
      )
  }

  updateRouteWidth(width) {
    this._routeWidth = width
    if (this.map?.getLayer(ROUTE_LAYER))
      this.map.setPaintProperty(ROUTE_LAYER, "line-width", width)
  }

  updateMarkerColor(color) {
    this._markerColor = color
    if (this.markerStyle === "dot") {
      if (this.map?.getLayer(MARKER_LAYER))
        this.map.setPaintProperty(MARKER_LAYER, "circle-color", color)
      if (this.map?.getLayer(MARKER_GLOW_LAYER))
        this.map.setPaintProperty(MARKER_GLOW_LAYER, "circle-color", color)
    } else if (this.arrowMarker) {
      const el = this.arrowMarker.getElement()
      if (el) el.style.borderBottomColor = color
    }
  }

  updateOrientation(orientation) {
    if (!this.map) return
    if (orientation === "portrait") {
      this.container.style.aspectRatio = "9 / 16"
      this.container.style.height = "280px"
      this.container.style.width = ""
      this.container.style.margin = "0 auto"
      this.container.classList.remove("w-full")
      this.wrapperEl.style.maxWidth = "fit-content"
      this.wrapperEl.style.margin = "0 auto"
    } else {
      this.container.style.aspectRatio = "16 / 9"
      this.container.style.height = ""
      this.container.style.width = ""
      this.container.style.margin = ""
      this.container.classList.add("w-full")
      this.wrapperEl.style.maxWidth = ""
      this.wrapperEl.style.margin = ""
    }
    this.map.resize()
    this._fitBounds()
  }

  updateLayout(name) {
    this.overlays.updateLayout(name)
  }

  updateOverlayVisibility(obj) {
    this.overlays.updateVisibility(obj)
  }

  updateTrackName(n) {
    this.overlays.updateTrackName(n)
  }

  updateMarkerStyle(value) {
    this.markerStyle = value
    if (this.map && this.coords) this._rebuildMarker()
  }

  applyAll(options) {
    if (!this.map) return

    const prevStyle = this._style
    const prevMarkerStyle = this.markerStyle

    // 1. Update all internal state
    if (options.routeColor != null) this._routeColor = options.routeColor
    if (options.routeWidth != null) this._routeWidth = options.routeWidth
    if (options.markerColor != null) this._markerColor = options.markerColor
    if (options.markerStyle != null) this.markerStyle = options.markerStyle
    if (options.style != null) this._style = options.style

    // 2. Update overlays synchronously
    if (options.layout != null) this.overlays.updateLayout(options.layout)
    if (options.overlays != null)
      this.overlays.updateVisibility(options.overlays)
    if (options.trackName != null)
      this.overlays.updateTrackName(options.trackName)

    // 3. Style change requires full reload
    if (this._style !== prevStyle) {
      this._reloadStyle()
    } else {
      // 4. No style change -- update paint properties directly
      if (this.map.getLayer(ROUTE_LAYER)) {
        this.map.setPaintProperty(
          ROUTE_LAYER,
          "line-gradient",
          buildGradient(this._routeColor),
        )
        this.map.setPaintProperty(ROUTE_LAYER, "line-width", this._routeWidth)
      }

      if (this.markerStyle !== prevMarkerStyle) {
        this._rebuildMarker()
      } else if (this.markerStyle === "dot") {
        if (this.map.getLayer(MARKER_LAYER))
          this.map.setPaintProperty(
            MARKER_LAYER,
            "circle-color",
            this._markerColor,
          )
        if (this.map.getLayer(MARKER_GLOW_LAYER))
          this.map.setPaintProperty(
            MARKER_GLOW_LAYER,
            "circle-color",
            this._markerColor,
          )
      } else if (this.arrowMarker) {
        const el = this.arrowMarker.getElement()
        if (el) el.style.borderBottomColor = this._markerColor
      }
    }
  }

  destroy() {
    this._destroyed = true
    this.overlays.destroy()
    if (this.arrowMarker) {
      this.arrowMarker.remove()
      this.arrowMarker = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
    this.coords = null
    this.bounds = null
  }

  // -- Private --------------------------------------------------------------

  async _loadCoords(trackId) {
    if (!trackId) return null
    try {
      const res = await fetch(`/api/v1/tracks/${trackId}`, {
        headers: { Authorization: `Bearer ${this.apiKey}` },
      })
      if (!res.ok) {
        console.warn(
          `[VideoExport] Failed to load track ${trackId}: ${res.status}`,
        )
        return null
      }
      return extractCoordsFromGeoJSON(await res.json())
    } catch (err) {
      console.warn(`[VideoExport] Error loading track ${trackId}:`, err)
      return null
    }
  }

  _reloadStyle() {
    getMapStyle(this._style).then((style) => {
      // Guard: if destroyed while the async style fetch was in flight, bail out
      if (this._destroyed || !this.map) return

      // Recreate the map instead of using setStyle() — avoids timing issues
      // in MapLibre v5 where layers added during style.load can be lost.
      this.map.remove()
      this.map = new maplibregl.Map({
        container: this.container,
        style,
        interactive: false,
        attributionControl: false,
      })
      this.map.on("load", () => {
        this._initLayers()
        this._fitBounds()
        this.overlays.updateTheme(this._style)
        this._updateOverlayStats()
      })
    })
  }

  _initLayers() {
    if (!this.coords) return
    addRouteLayers(this.map, this.coords, {
      routeColor: this._routeColor,
      routeWidth: this._routeWidth,
    })
    this._rebuildMarker()
  }

  _rebuildMarker() {
    if (this.arrowMarker) {
      this.arrowMarker.remove()
      this.arrowMarker = null
    }
    if (this.map.getLayer(MARKER_GLOW_LAYER))
      this.map.removeLayer(MARKER_GLOW_LAYER)
    if (this.map.getLayer(MARKER_LAYER)) this.map.removeLayer(MARKER_LAYER)

    if (this.markerStyle === "arrow") {
      this.arrowMarker = addArrowMarker(
        this.map,
        this.coords,
        this._markerColor,
      )
    } else {
      addDotLayers(this.map, this._markerColor)
    }
  }

  _fitBounds() {
    if (!this.coords?.length) return
    const bounds = new maplibregl.LngLatBounds()
    for (const c of this.coords) bounds.extend([c.lon, c.lat])
    if (!bounds.isEmpty()) {
      this.bounds = bounds
      this.map.fitBounds(bounds, { padding: 40, maxZoom: 15, duration: 0 })
    }
  }

  _updateOverlayStats() {
    if (!this.coords?.length) return
    const last = this.coords[this.coords.length - 1]
    const first = this.coords[0]
    this.overlays.updateFrame({
      elapsedSeconds: last.timestamp - first.timestamp,
      speed: 0,
      distance: cumulativeDistance(this.coords, 1),
    })
  }
}
