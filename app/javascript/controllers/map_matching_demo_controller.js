import { Controller } from "@hotwired/stimulus"
import * as maplibregl from "maplibre-gl"
import { getCurrentTheme } from "maps_maplibre/utils/popup_theme"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

// A synthetic 2.6 km walk through central Berlin, from Alexanderplatz to the
// Brandenburg Gate. The original trace deliberately carries realistic GPS
// drift; the matched trace follows Karl-Liebknecht-Straße and Unter den Linden.
export const MATCHED_PATH = [
  [13.41315, 52.52188],
  [13.4107, 52.521],
  [13.40815, 52.52005],
  [13.40565, 52.51912],
  [13.40305, 52.51812],
  [13.40125, 52.51712],
  [13.3977, 52.51702],
  [13.39365, 52.51678],
  [13.38925, 52.51655],
  [13.38465, 52.51632],
  [13.38055, 52.51622],
  [13.37772, 52.51627],
]

export const ORIGINAL_PATH = [
  [13.41315, 52.52188],
  [13.4111, 52.5215],
  [13.409, 52.5201],
  [13.4073, 52.5197],
  [13.4053, 52.5196],
  [13.4028, 52.5184],
  [13.4009, 52.5176],
  [13.3983, 52.5166],
  [13.3954, 52.5173],
  [13.3921, 52.5164],
  [13.3889, 52.5169],
  [13.385, 52.5159],
  [13.3814, 52.5166],
  [13.37772, 52.51627],
]

const MODES = new Set(["original", "matched"])

function lineFeature(coordinates) {
  return {
    type: "Feature",
    properties: {},
    geometry: { type: "LineString", coordinates },
  }
}

export default class extends Controller {
  static targets = ["map", "button", "loading"]

  connect() {
    this.mode = "matched"
    this.updateButtonState()
    requestAnimationFrame(() => this.initializeMap())
  }

  disconnect() {
    this.map?.remove()
    this.map = null
  }

  async initializeMap() {
    try {
      const style = await getMapStyle(getCurrentTheme())

      this.map = new maplibregl.Map({
        container: this.mapTarget,
        style,
        center: [13.3954, 52.5185],
        zoom: 14,
        attributionControl: false,
        scrollZoom: false,
        dragRotate: false,
        pitchWithRotate: false,
      })

      this.map.addControl(
        new maplibregl.NavigationControl({ showCompass: false }),
        "top-right",
      )
      this.map.addControl(
        new maplibregl.AttributionControl({ compact: true }),
        "bottom-right",
      )
      this.map.on("load", () => this.addDemoLayers())
    } catch (error) {
      console.error("Map matching demo failed to initialize:", error)
    }
  }

  select(event) {
    this.showMode(event.currentTarget.dataset.mode)
  }

  showMode(mode) {
    if (!MODES.has(mode)) return

    this.mode = mode
    this.updateButtonState()
    if (!this.map || !this.routeReady) return

    const showingOriginal = mode === "original"
    this.map.setPaintProperty(
      "map-matching-demo-original-halo",
      "line-opacity",
      showingOriginal ? 0.85 : 0.28,
    )
    this.map.setPaintProperty(
      "map-matching-demo-original",
      "line-opacity",
      showingOriginal ? 1 : 0.42,
    )
    this.map.setPaintProperty(
      "map-matching-demo-matched-halo",
      "line-opacity",
      showingOriginal ? 0 : 0.9,
    )
    this.map.setPaintProperty(
      "map-matching-demo-matched",
      "line-opacity",
      showingOriginal ? 0 : 1,
    )
  }

  updateButtonState() {
    for (const button of this.buttonTargets) {
      const active = button.dataset.mode === this.mode
      button.setAttribute("aria-pressed", String(active))
      button.classList.toggle("btn-ghost", !active)
      button.classList.toggle("btn-outline", !active)
      button.classList.toggle(
        "btn-warning",
        active && button.dataset.mode === "original",
      )
      button.classList.toggle(
        "btn-success",
        active && button.dataset.mode === "matched",
      )
    }
  }

  addDemoLayers() {
    this.map.addSource("map-matching-demo-original", {
      type: "geojson",
      data: lineFeature(ORIGINAL_PATH),
    })
    this.map.addSource("map-matching-demo-matched", {
      type: "geojson",
      data: lineFeature(MATCHED_PATH),
    })
    this.map.addSource("map-matching-demo-endpoints", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [ORIGINAL_PATH[0], ORIGINAL_PATH.at(-1)].map(
          (coordinates) => ({
            type: "Feature",
            properties: {},
            geometry: { type: "Point", coordinates },
          }),
        ),
      },
    })

    this.addRouteLayer("original-halo", "original", {
      "line-color": "#ffffff",
      "line-width": 9,
      "line-opacity": 0.28,
    })
    this.addRouteLayer("original", "original", {
      "line-color": "#f59e0b",
      "line-width": 5,
      "line-dasharray": [1.1, 1.1],
      "line-opacity": 0.42,
    })
    this.addRouteLayer("matched-halo", "matched", {
      "line-color": "#ffffff",
      "line-width": 9,
      "line-opacity": 0.9,
    })
    this.addRouteLayer("matched", "matched", {
      "line-color": "#0d9488",
      "line-width": 5,
      "line-opacity": 1,
    })
    this.map.addLayer({
      id: "map-matching-demo-endpoints",
      type: "circle",
      source: "map-matching-demo-endpoints",
      paint: {
        "circle-radius": 5,
        "circle-color": "#0d9488",
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 3,
      },
    })

    const bounds = new maplibregl.LngLatBounds()
    for (const coordinates of MATCHED_PATH) bounds.extend(coordinates)
    this.map.fitBounds(bounds, {
      padding: { top: 44, right: 36, bottom: 76, left: 36 },
      duration: 0,
      maxZoom: 15,
    })

    this.routeReady = true
    this.showMode(this.mode)
    if (this.hasLoadingTarget) this.loadingTarget.remove()
  }

  addRouteLayer(suffix, source, paint) {
    this.map.addLayer({
      id: `map-matching-demo-${suffix}`,
      type: "line",
      source: `map-matching-demo-${source}`,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: {
        ...paint,
        "line-opacity-transition": { duration: 240, delay: 0 },
      },
    })
  }
}
