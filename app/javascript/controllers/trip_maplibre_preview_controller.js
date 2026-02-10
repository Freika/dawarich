import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import maplibregl from "maplibre-gl"

/**
 * Lightweight MapLibre controller for trip card previews on the index page.
 * Renders a static, non-interactive map with the trip path as a single line.
 */
export default class extends Controller {
  static values = {
    path: String,
    mapStyle: { type: String, default: "light" },
  }

  async connect() {
    this.map = await MapInitializer.initialize(this.element, {
      mapStyle: this.mapStyleValue,
      center: [0, 0],
      zoom: 2,
      showControls: false,
    })

    // Disable all interaction for a static preview
    this.map.dragPan.disable()
    this.map.scrollZoom.disable()
    this.map.boxZoom.disable()
    this.map.dragRotate.disable()
    this.map.doubleClickZoom.disable()
    this.map.touchZoomRotate.disable()
    this.map.keyboard.disable()

    this.map.on("load", () => {
      this.showRoute()
    })
  }

  showRoute() {
    if (!this.hasPathValue || !this.pathValue) return

    let coordinates
    try {
      coordinates = JSON.parse(this.pathValue)
    } catch (_e) {
      return
    }

    if (!coordinates.length) return

    this.map.addSource("trip-path", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates,
        },
      },
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

    const bounds = new maplibregl.LngLatBounds()
    for (const coord of coordinates) {
      bounds.extend(coord)
    }
    if (!bounds.isEmpty()) {
      this.map.fitBounds(bounds, { padding: 20, maxZoom: 15, animate: false })
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
