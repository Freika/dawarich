import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import * as maplibregl from "maplibre-gl"
import { TripPlanLayer } from "maps_maplibre/layers/trip_plan_layer"
import { ApiClient } from "maps_maplibre/services/api_client"
import { RouteSegmenter } from "maps_maplibre/utils/route_segmenter"

const TILE_SOURCE = "trip-route-tiles"
const TILE_LAYER = "trip-route-tiles-layer"

/**
 * Lightweight MapLibre controller for trip route previews.
 * Draws the trip route from vector tiles as a single line. Used as a static,
 * non-interactive preview on trip cards, and as an interactive live preview
 * on the trip form, where it shows the tracks of the chosen date range
 * (trip-range-updated). A trip without a recorded route shows its plan
 * instead, when it has one.
 */
export default class extends Controller {
  static values = {
    tilesUrl: String,
    bounds: Array,
    apiKey: String,
    lines: String,
    linesUrl: String,
    plan: String,
    numbered: { type: Boolean, default: false },
    mapStyle: { type: String, default: "light" },
    interactive: { type: Boolean, default: false },
  }

  async connect() {
    this.map = await MapInitializer.initialize(
      this.element,
      {
        mapStyle: this.mapStyleValue,
        center: [0, 0],
        zoom: 2,
        showControls: this.interactiveValue,
      },
      this.apiKeyValue || null,
    )

    if (!this.interactiveValue) {
      this.map.dragPan.disable()
      this.map.scrollZoom.disable()
      this.map.boxZoom.disable()
      this.map.dragRotate.disable()
      this.map.doubleClickZoom.disable()
      this.map.touchZoomRotate.disable()
      this.map.keyboard.disable()
    }

    this.onRangeUpdated = (event) => this.showRange(event.detail)
    this.element.addEventListener("trip-range-updated", this.onRangeUpdated)

    this.onPlanFocus = (event) => {
      const { longitude, latitude } = event.detail || {}
      if (Number.isFinite(longitude) && Number.isFinite(latitude))
        this.planLayer?.focus(longitude, latitude)
    }
    window.addEventListener("trip-plan:focus", this.onPlanFocus)

    this.map.on("load", () => {
      this.mapLoaded = true
      if (this.pendingRange) this._renderTiles(...this.pendingRange)
      else if (this.hasLinesUrlValue) this.loadLines()
      else if (!this.showRoute()) this.showPlan()
    })
  }

  async loadLines() {
    let lines
    try {
      const response = await fetch(this.linesUrlValue, {
        headers: { Accept: "application/json" },
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      lines = (await response.json()).lines || []
    } catch (error) {
      console.error("Failed to load routes:", error)
      return
    }
    if (!this.map) return

    if (lines.length) {
      this.linesValue = JSON.stringify(lines)
      this.showLines()
    } else {
      this.element.closest("[data-map-wrapper]")?.remove()
    }
  }

  showRoute() {
    if (this.showLines()) return true
    if (!this.tilesUrlValue) return false

    this._renderTiles(this.tilesUrlValue, "trip_routes", this.boundsValue)
    return true
  }

  async showRange({ startAt, endAt }) {
    if (!this.map) return
    this.rangeRequest = (this.rangeRequest || 0) + 1
    const request = this.rangeRequest

    let extent
    try {
      extent = await new ApiClient(this.apiKeyValue).fetchHistoryBounds({
        start_at: startAt,
        end_at: endAt,
      })
    } catch (error) {
      console.error("Failed to load the trip range:", error)
      return
    }
    if (!this.map || !extent || request !== this.rangeRequest) return

    const params = new URLSearchParams({ start_at: startAt, end_at: endAt })
    const tiles = [
      `/api/v1/tiles/tracks/{z}/{x}/{y}.mvt?${params}`,
      "tracks",
      [
        [extent.min_lng, extent.min_lat],
        [extent.max_lng, extent.max_lat],
      ],
    ]
    if (this.mapLoaded) this._renderTiles(...tiles)
    else this.pendingRange = tiles
  }

  showLines() {
    if (!this.hasLinesValue || !this.linesValue) return false

    let lines
    try {
      lines = JSON.parse(this.linesValue)
    } catch (_e) {
      return false
    }
    if (!lines.length) return false

    this._renderLines(
      lines.flatMap((line) =>
        RouteSegmenter.unwrapCoordinates(
          line.map(([lon, lat]) => ({ longitude: lon, latitude: lat })),
        ),
      ),
    )
    return true
  }

  showPlan() {
    if (!this.hasPlanValue || !this.planValue) return

    let plan
    try {
      plan = JSON.parse(this.planValue)
    } catch (_e) {
      return
    }
    if (!plan?.features?.length) return

    this.planLayer = new TripPlanLayer(this.map, {
      numbered: this.numberedValue,
    })
    this.planLayer.add(plan)
  }

  _renderTiles(tilesUrl, sourceLayer, bounds) {
    this.planLayer?.remove()
    this.planLayer = null
    if (this.map.getLayer(TILE_LAYER)) this.map.removeLayer(TILE_LAYER)
    if (this.map.getSource(TILE_SOURCE)) this.map.removeSource(TILE_SOURCE)

    this.map.addSource(TILE_SOURCE, {
      type: "vector",
      tiles: [tilesUrl],
      minzoom: 0,
      maxzoom: 22,
    })
    this.map.addLayer({
      id: TILE_LAYER,
      type: "line",
      source: TILE_SOURCE,
      "source-layer": sourceLayer,
      layout: { "line-join": "round", "line-cap": "round" },
      paint: {
        "line-color": "#6366F1",
        "line-width": 3,
        "line-opacity": 0.9,
      },
    })

    if (bounds?.length === 2) {
      this.map.fitBounds(bounds, { padding: 20, maxZoom: 15, animate: false })
    }
  }

  _renderLines(lineStrings) {
    const data = {
      type: "Feature",
      geometry: {
        type: "MultiLineString",
        coordinates: lineStrings,
      },
    }

    const source = this.map.getSource("trip-path")
    if (source) {
      source.setData(data)
    } else {
      this.map.addSource("trip-path", {
        type: "geojson",
        data: data,
      })

      this.map.addLayer({
        id: "trip-path-layer",
        type: "line",
        source: "trip-path",
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.9,
        },
      })
    }

    const bounds = new maplibregl.LngLatBounds()
    for (const line of lineStrings) {
      for (const coord of line) {
        bounds.extend(coord)
      }
    }
    if (!bounds.isEmpty()) {
      this.map.fitBounds(bounds, { padding: 20, maxZoom: 15, animate: false })
    }
  }

  disconnect() {
    this.element.removeEventListener("trip-range-updated", this.onRangeUpdated)
    window.removeEventListener("trip-plan:focus", this.onPlanFocus)
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
