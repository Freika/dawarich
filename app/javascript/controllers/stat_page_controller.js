import { translate } from "i18n"
import maplibregl from "maplibre-gl"
import { getCurrentTheme } from "maps_maplibre/utils/popup_theme"
import { getMapStyle } from "maps_maplibre/utils/style_manager"
import BaseController from "./base_controller"

const HEATMAP_PAINT = {
  "heatmap-weight": 0.5,
  "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 0, 1, 15, 1.5],
  "heatmap-color": [
    "interpolate",
    ["linear"],
    ["heatmap-density"],
    0,
    "rgba(0,0,255,0)",
    0.4,
    "rgb(0,0,255)",
    0.6,
    "rgb(0,255,255)",
    0.7,
    "rgb(0,255,0)",
    0.8,
    "rgb(255,255,0)",
    1,
    "rgb(255,0,0)",
  ],
  "heatmap-radius": [
    "interpolate",
    ["exponential", 1.5],
    ["zoom"],
    10,
    8,
    13,
    15,
    15,
    25,
  ],
  "heatmap-opacity": 0.8,
}

export default class extends BaseController {
  static targets = ["map", "loading", "heatmapBtn", "pointsBtn"]

  connect() {
    super.connect()

    this.year = Number.parseInt(
      this.element.dataset.year || `${new Date().getFullYear()}`,
      10,
    )
    this.month = Number.parseInt(
      this.element.dataset.month || `${new Date().getMonth() + 1}`,
      10,
    )
    this.apiKey = this.element.dataset.apiKey
    this.initializeMap()
  }

  disconnect() {
    this.disconnected = true
    if (this.map) {
      this.map.remove()
    }
  }

  async initializeMap() {
    try {
      const style = await getMapStyle(getCurrentTheme(), {
        vectorTilesUrl: this.element.dataset.tilesUrl || null,
      })
      if (this.disconnected) return

      this.map = new maplibregl.Map({
        container: this.mapTarget,
        style,
        center: [13.404954, 52.520008],
        zoom: 10,
        attributionControl: false,
      })
      this.map.addControl(
        new maplibregl.NavigationControl({ showCompass: false }),
        "top-right",
      )
      this.map.addControl(new maplibregl.AttributionControl({ compact: true }))
      this.map.addControl(
        new maplibregl.ScaleControl({ maxWidth: 100 }),
        "bottom-right",
      )
      this.map.on("load", () => this.loadMonthData())
    } catch (error) {
      console.error("Error initializing map:", error)
      this.showError(translate("stats.map_initialization_failed"))
    }
  }

  async loadMonthData() {
    this.messageShown = false

    try {
      this.showLoading(true)

      const startDate = `${this.year}-${this.month.toString().padStart(2, "0")}-01T00:00:00`
      const lastDay = new Date(this.year, this.month, 0).getDate()
      const endDate = `${this.year}-${this.month.toString().padStart(2, "0")}-${lastDay}T23:59:59`

      const points = await this.fetchAllPoints(startDate, endDate)
      if (this.disconnected) return

      const coordinates = points
        .map((point) => [
          Number.parseFloat(point.longitude),
          Number.parseFloat(point.latitude),
        ])
        .filter(
          ([lng, lat]) =>
            !Number.isNaN(lat) && !Number.isNaN(lng) && lat !== 0 && lng !== 0,
        )

      if (coordinates.length > 0) {
        this.renderLayers(coordinates)
      } else {
        this.showNoData()
      }
    } catch (error) {
      console.error("Error loading month data:", error)
      this.showError(translate("stats.location_data_load_failed"))
    } finally {
      if (!this.disconnected && !this.messageShown) this.showLoading(false)
    }
  }

  async fetchAllPoints(startDate, endDate) {
    const allPoints = []
    let page = 1

    while (true) {
      const response = await fetch(
        `/api/v1/points?slim=true&start_at=${encodeURIComponent(startDate)}&end_at=${encodeURIComponent(endDate)}&per_page=1000&page=${page}`,
        {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.apiKey}`,
          },
        },
      )

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      if (!Array.isArray(data) || data.length === 0) break

      allPoints.push(...data)

      const totalPages = Number.parseInt(
        response.headers.get("X-Total-Pages"),
        10,
      )
      if (!totalPages || page >= totalPages) break

      page++
    }

    return allPoints
  }

  renderLayers(coordinates) {
    this.map.addSource("stat-points", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: coordinates.map((lngLat) => ({
          type: "Feature",
          geometry: { type: "Point", coordinates: lngLat },
          properties: {},
        })),
      },
    })
    this.map.addLayer({
      id: "stat-heatmap",
      type: "heatmap",
      source: "stat-points",
      paint: HEATMAP_PAINT,
    })
    this.map.addLayer({
      id: "stat-circles",
      type: "circle",
      source: "stat-points",
      layout: { visibility: "none" },
      paint: {
        "circle-radius": 3,
        "circle-color": "#570df8",
        "circle-opacity": 0.6,
        "circle-stroke-width": 1,
        "circle-stroke-color": "#570df8",
        "circle-stroke-opacity": 0.8,
      },
    })

    const bounds = coordinates.reduce(
      (acc, lngLat) => acc.extend(lngLat),
      new maplibregl.LngLatBounds(coordinates[0], coordinates[0]),
    )
    this.map.fitBounds(bounds, { padding: 40, maxZoom: 14, duration: 0 })

    this.heatmapBtnTarget.classList.add("btn-active")
    this.pointsBtnTarget.classList.remove("btn-active")
  }

  layerVisible(id) {
    return this.map.getLayoutProperty(id, "visibility") !== "none"
  }

  setLayerVisible(id, visible) {
    this.map.setLayoutProperty(id, "visibility", visible ? "visible" : "none")
  }

  toggleHeatmap() {
    if (!this.map?.getLayer("stat-heatmap")) return

    if (this.layerVisible("stat-heatmap")) {
      this.setLayerVisible("stat-heatmap", false)
      this.heatmapBtnTarget.classList.remove("btn-active")
      this.setLayerVisible("stat-circles", true)
      this.pointsBtnTarget.classList.add("btn-active")
    } else {
      this.setLayerVisible("stat-heatmap", true)
      this.heatmapBtnTarget.classList.add("btn-active")
      this.setLayerVisible("stat-circles", false)
      this.pointsBtnTarget.classList.remove("btn-active")
    }
  }

  togglePoints() {
    if (!this.map?.getLayer("stat-circles")) return

    if (this.layerVisible("stat-circles")) {
      this.setLayerVisible("stat-circles", false)
      this.pointsBtnTarget.classList.remove("btn-active")
    } else {
      this.setLayerVisible("stat-circles", true)
      this.pointsBtnTarget.classList.add("btn-active")
      this.setLayerVisible("stat-heatmap", false)
      this.heatmapBtnTarget.classList.remove("btn-active")
    }
  }

  showLoading(show) {
    if (this.hasLoadingTarget) {
      this.loadingTarget.style.display = show ? "flex" : "none"
    }
  }

  showError(message) {
    if (!this.hasLoadingTarget) return

    this.messageShown = true
    const container = document.createElement("div")
    container.className = "alert alert-error"
    const span = document.createElement("span")
    span.textContent = message
    container.appendChild(span)
    this.loadingTarget.replaceChildren(container)
    this.loadingTarget.style.display = "flex"
  }

  showNoData() {
    if (!this.hasLoadingTarget) return

    this.messageShown = true
    const dateLabel = new Date(this.year, this.month - 1).toLocaleDateString(
      document.documentElement.lang || undefined,
      { month: "long", year: "numeric" },
    )
    const container = document.createElement("div")
    container.className = "alert alert-info"
    const span = document.createElement("span")
    span.textContent = translate("stats.no_location_data", { date: dateLabel })
    container.appendChild(span)
    this.loadingTarget.replaceChildren(container)
    this.loadingTarget.style.display = "flex"
  }
}
