import maplibregl from "maplibre-gl"
import {
  planBounds,
  planDayColorExpression,
  planDayCount,
  planMarkers,
} from "../utils/trip_plan"
import { DayRoutesLayer } from "./day_routes_layer"

const SOURCE_ID = "trip-plan"
const ROUTE_LAYER_ID = "trip-plan-routes"
const STOP_LAYER_ID = "trip-plan-stops"
const PLACE_LAYER_ID = "trip-plan-places"
const STAY_COLOR = "#0D9488"

/**
 * Draws a planned itinerary: a dashed line through each day's stops (dashed
 * so it never reads as a recorded track), the stops, stays and loose places.
 * `numbered` swaps the stop dots for numbered markers matching the plan card.
 */
export class TripPlanLayer {
  constructor(map, { numbered = false } = {}) {
    this.map = map
    this.numbered = numbered
    this.markers = []
  }

  add(plan) {
    this.remove()
    const palette = DayRoutesLayer.generateDayPalette(
      Math.max(planDayCount(plan), 1),
    )
    const dayColor = planDayColorExpression(palette)

    this.map.addSource(SOURCE_ID, { type: "geojson", data: plan })
    this.map.addLayer({
      id: ROUTE_LAYER_ID,
      type: "line",
      source: SOURCE_ID,
      filter: ["==", ["get", "kind"], "route"],
      layout: { "line-join": "round", "line-cap": "round" },
      paint: {
        "line-color": dayColor,
        "line-width": 3,
        "line-opacity": 0.85,
        "line-dasharray": [1.5, 1.5],
      },
    })
    this.map.addLayer({
      id: PLACE_LAYER_ID,
      type: "circle",
      source: SOURCE_ID,
      filter: ["in", ["get", "kind"], ["literal", ["stay", "unplanned"]]],
      paint: {
        "circle-radius": 5,
        "circle-color": [
          "case",
          ["==", ["get", "kind"], "stay"],
          STAY_COLOR,
          "rgba(255, 255, 255, 0.9)",
        ],
        "circle-stroke-width": 2,
        "circle-stroke-color": [
          "case",
          ["==", ["get", "kind"], "stay"],
          "#ffffff",
          STAY_COLOR,
        ],
      },
    })

    if (this.numbered) {
      this.markers = planMarkers(plan, palette).map((stop) =>
        new maplibregl.Marker({ element: this._markerElement(stop) })
          .setLngLat(stop.coordinates)
          .addTo(this.map),
      )
    } else {
      this.map.addLayer({
        id: STOP_LAYER_ID,
        type: "circle",
        source: SOURCE_ID,
        filter: ["==", ["get", "kind"], "stop"],
        paint: {
          "circle-radius": 4,
          "circle-color": dayColor,
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff",
        },
      })
    }

    const bounds = planBounds(plan)
    if (bounds) {
      this.map.fitBounds(bounds, { padding: 40, maxZoom: 14, animate: false })
    }
  }

  focus(longitude, latitude) {
    this.map.flyTo({ center: [longitude, latitude], zoom: 15, duration: 600 })
  }

  remove() {
    for (const marker of this.markers) marker.remove()
    this.markers = []
    for (const id of [STOP_LAYER_ID, PLACE_LAYER_ID, ROUTE_LAYER_ID]) {
      if (this.map.getLayer(id)) this.map.removeLayer(id)
    }
    if (this.map.getSource(SOURCE_ID)) this.map.removeSource(SOURCE_ID)
  }

  _markerElement({ number, name, color }) {
    const element = document.createElement("div")
    element.className = "trip-plan-marker"
    element.style.setProperty("--trip-plan-marker-color", color)
    element.textContent = String(number)
    element.title = name
    element.setAttribute("aria-label", `${number}. ${name}`)
    return element
  }
}
