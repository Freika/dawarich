import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"
import { FogHexagonSource } from "maps_maplibre/layers/fog_hexagon_source"
import { FogLayer } from "maps_maplibre/layers/fog_layer"
import { ApiClient } from "maps_maplibre/services/api_client"

/**
 * Standalone Fog of War map controller
 *
 * Renders a full-screen MapLibre map with only the Fog of War canvas overlay.
 * Loads fog hexagon cell ids from /api/v1/maps/hexagons/fog and optionally
 * clears circles around points fetched from the points API.
 * No track/route/visit/etc. layers are loaded.
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String,
    timezone: String,
  }

  static targets = ["container", "progressBadge", "progressBadgeText", "hexagonsMode", "pointsMode"]

  async connect() {
    this.map = null
    this.fogLayer = null
    this.api = new ApiClient(this.apiKeyValue)
    this.hexSource = new FogHexagonSource()
    this.mode = "hexagons" // default mode
    this.pointsCache = null
    this._abortController = null

    await this.initializeMap()
    this.showLoading("Loading fog data...")
    await this.loadFogData()
    this.hideLoading()
  }

  disconnect() {
    if (this._abortController) {
      this._abortController.abort()
    }
    if (this.fogLayer) {
      this.fogLayer.remove()
    }
    if (this.map) {
      this.map.remove()
    }
  }

  // ---- Initialization ----

  async initializeMap() {
    const style = await getMapStyle("dark", {})

    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style,
      center: [0, 0],
      zoom: 2,
      attributionControl: false,
    })

    this.map.addControl(new maplibregl.NavigationControl(), "top-right")
    this.map.addControl(new maplibregl.AttributionControl({ compact: true }), "bottom-right")

    // Wait for style to load before creating fog layer
    await new Promise((resolve) => {
      if (this.map.isStyleLoaded()) {
        resolve()
      } else {
        this.map.once("style.load", resolve)
      }
    })

    // Create empty fog layer
    this.fogLayer = new FogLayer(this.map, {
      clearRadius: 1000,
      visible: true,
      mode: this.mode,
      api: this.api,
    })
    this.fogLayer.add({
      type: "FeatureCollection",
      features: [],
    })
    this.fogLayer.show()

    // Re-render fog on map interactions
    this.map.on("move", () => this.fogLayer?.render())
    this.map.on("zoom", () => this.fogLayer?.render())

    // Recalculate hex boundaries on zoom end
    let zoomTimer = null
    this.map.on("zoomend", () => {
      if (zoomTimer) clearTimeout(zoomTimer)
      zoomTimer = setTimeout(() => {
        if (this.mode === "hexagons" && this.hexSource.loaded) {
          if (this.hexSource.resolutionChanged(this.map.getZoom())) {
            const boundaries = this.hexSource.boundariesFor(this.map.getZoom())
            this._applyHexBoundaries(boundaries)
          }
        }
      }, 250)
    })
  }

  // ---- Data Loading ----

  async loadFogData() {
    const start = this.startDateValue
    const end = this.endDateValue

    this.showLoading("Loading fog data...")

    try {
      await this.hexSource.load(this.api, { start_at: start, end_at: end })

      if (this.mode === "hexagons") {
        const boundaries = this.hexSource.boundariesFor(this.map.getZoom())
        this._applyHexBoundaries(boundaries)
      }

      // Also fetch points for points mode — minimal data, no rendering on map
      if (this.mode === "points") {
        await this._ensurePointsLoaded()
      }

      // Fit map to available data bounds
      await this._fitToBounds()
    } catch (error) {
      console.error("[FogMap] Failed to load fog data:", error)
      this.showLoading("Failed to load data")
      setTimeout(() => this.hideLoading(), 2000)
    }
  }

  async _ensurePointsLoaded() {
    if (this.pointsCache) return

    const start = this.startDateValue
    const end = this.endDateValue

    try {
      const result = await this.api.fetchAllPoints({
        start_at: start,
        end_at: end,
        maxConcurrent: 3,
      })

      this.pointsCache = {
        type: "FeatureCollection",
        features: result.points.map((p) => ({
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [parseFloat(p.longitude), parseFloat(p.latitude)],
          },
          properties: {},
        })),
      }

      // Update fog layer with point data
      if (this.fogLayer && this.mode === "points") {
        this.fogLayer.update(this.pointsCache)
        this.fogLayer.render()
      }
    } catch (error) {
      console.error("[FogMap] Failed to load points:", error)
    }
  }

  async _fitToBounds() {
    if (!this.hexSource.loaded || this.hexSource.rawCellIds.length === 0) return

    const h3 = this.hexSource.h3
    if (!h3) return

    // Compute bounds from the first few hexagon centers
    const sampleSize = Math.min(this.hexSource.rawCellIds.length, 50)
    const coords = []
    for (let i = 0; i < sampleSize; i++) {
      const id = this.hexSource.rawCellIds[i]
      if (h3.isValidCell(id)) {
        const [lat, lng] = h3.cellToLatLng(id)
        coords.push([lng, lat])
      }
    }

    if (coords.length === 0) return

    const bounds = coords.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coords[0], coords[0]),
    )

    this.map.fitBounds(bounds, { padding: 50, maxZoom: 12 })
  }

  // ---- Mode Switching ----

  switchMode(event) {
    const newMode = event.target.value
    if (newMode === this.mode) return

    this.mode = newMode

    if (!this.fogLayer) return

    // Update fog layer mode
    if (this.mode === "hexagons") {
      if (this.hexSource.loaded) {
        const boundaries = this.hexSource.boundariesFor(this.map.getZoom())
        this._applyHexBoundaries(boundaries)
      }
      this.fogLayer.mode = "hexagons"
    } else {
      // Points mode — need points data
      this.fogLayer.mode = "points"
      this._ensurePointsLoaded().then(() => {
        if (this.pointsCache) {
          this.fogLayer.update(this.pointsCache)
        }
        this.fogLayer.render()
      })
    }

    this.fogLayer.render()
  }

  // ---- Helpers ----

  _applyHexBoundaries(boundaries) {
    if (!this.fogLayer) return
    this.fogLayer.hexBoundaries = boundaries
    this.fogLayer.render()
  }

  showLoading(message) {
    const badge = this.progressBadgeTarget
    if (badge) {
      badge.classList.add("visible")
      const text = this.progressBadgeTextTarget
      if (text) text.textContent = message
    }
  }

  hideLoading() {
    const badge = this.progressBadgeTarget
    if (badge) {
      badge.classList.remove("visible")
    }
  }
}