import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import maplibregl from "maplibre-gl"
import { RouteSegmenter } from "maps_maplibre/utils/route_segmenter"

/**
 * Lightweight MapLibre controller for trip path previews.
 * Renders the trip path as a single line. Used as a static, non-interactive
 * preview on trip cards, and as an interactive live preview on the trip
 * form, where it redraws when the date range changes (coordinates-updated).
 */
export default class extends Controller {
  static values = {
    path: String,
    mapStyle: { type: String, default: "light" },
    interactive: { type: Boolean, default: false },
  }

  async connect() {
    this.map = await MapInitializer.initialize(this.element, {
      mapStyle: this.mapStyleValue,
      center: [0, 0],
      zoom: 2,
      showControls: this.interactiveValue,
    })

    if (!this.interactiveValue) {
      this.map.dragPan.disable()
      this.map.scrollZoom.disable()
      this.map.boxZoom.disable()
      this.map.dragRotate.disable()
      this.map.doubleClickZoom.disable()
      this.map.touchZoomRotate.disable()
      this.map.keyboard.disable()
    }

    this.onCoordinatesUpdated = (event) => {
      this.updateFromPoints(event.detail.coordinates)
    }
    this.element.addEventListener(
      "coordinates-updated",
      this.onCoordinatesUpdated,
    )

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

    const segment = coordinates.map(([lon, lat]) => ({
      longitude: lon,
      latitude: lat,
    }))
    this._renderSegment(segment)
  }

  /**
   * Redraw the route from raw point objects (latitude/longitude/timestamp),
   * e.g. when the trip form's date range changes.
   */
  updateFromPoints(points) {
    if (!this.map || !points) return

    const segment = points
      .slice()
      .sort((a, b) => a.timestamp - b.timestamp)
      .map((point) => ({
        longitude: Number(point.longitude),
        latitude: Number(point.latitude),
      }))
      .filter((p) => !Number.isNaN(p.longitude) && !Number.isNaN(p.latitude))

    this._renderSegment(segment)
  }

  _renderSegment(segment) {
    if (!segment.length) return

    const lineStrings = RouteSegmenter.unwrapCoordinates(segment)
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
    this.element.removeEventListener(
      "coordinates-updated",
      this.onCoordinatesUpdated,
    )
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
