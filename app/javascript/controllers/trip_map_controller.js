// This controller is being used on:
// - trips/index (card thumbnails)

import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    tripId: Number,
    path: String,
    apiKey: String,
    userSettings: Object,
    timezone: String,
  }

  connect() {
    requestAnimationFrame(() => this.initializeMap())
  }

  async initializeMap() {
    try {
      const container = this.element
      if (!container || container.clientHeight < 20) {
        setTimeout(() => this.initializeMap(), 200)
        return
      }

      const isDark = document.documentElement
        .getAttribute("data-theme")
        ?.includes("dark")
      const style = await getMapStyle(isDark ? "dark" : "light")

      this.map = new maplibregl.Map({
        container,
        style,
        center: [0, 0],
        zoom: 1,
        attributionControl: false,
        interactive: false,
      })

      this.map.on("load", () => {
        if (this.hasPathValue && this.pathValue) {
          this.showRoute()
        }
      })
    } catch (error) {
      console.error("TripMap init failed:", error)
    }
  }

  showRoute() {
    const coordinates = this.getCoordinates(this.pathValue)
    if (coordinates.length < 2) return

    this.map.addSource("trip-route", {
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
      id: "trip-route-line",
      type: "line",
      source: "trip-route",
      paint: {
        "line-color": "#3B82F6",
        "line-width": 3,
        "line-opacity": 0.8,
      },
      layout: {
        "line-join": "round",
        "line-cap": "round",
      },
    })

    // Fit bounds to route
    const bounds = new maplibregl.LngLatBounds()
    coordinates.forEach((coord) => bounds.extend(coord))
    this.map.fitBounds(bounds, { padding: 30, maxZoom: 15, duration: 0 })
  }

  getCoordinates(pathData) {
    try {
      let coordinates = pathData
      if (typeof pathData === "string") {
        coordinates = JSON.parse(pathData)
      }

      // Coordinates are already [lng, lat] from PostGIS — MapLibre uses the same order
      return coordinates.filter(
        (coord) =>
          Array.isArray(coord) &&
          coord.length >= 2 &&
          !Number.isNaN(coord[0]) &&
          !Number.isNaN(coord[1]),
      )
    } catch (error) {
      console.error("Error processing coordinates:", error)
      return []
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
