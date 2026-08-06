import maplibregl from "maplibre-gl"
import { buildHexagonPopup } from "maps_maplibre/utils/hexagon_popup"
import { getMapStyle } from "maps_maplibre/utils/style_manager"
import BaseController from "./base_controller"

export default class extends BaseController {
  static values = {
    year: Number,
    month: Number,
    uuid: String,
    dataBounds: Object,
    hexagonsAvailable: Boolean,
    timezone: String,
  }

  connect() {
    super.connect()
    this.hoveredId = null
    this.initializeMap()
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
    }
  }

  async initializeMap() {
    try {
      const style = await getMapStyle(this.styleName())
      this.map = new maplibregl.Map({
        container: this.element,
        style,
        center: [-100.0, 40.0],
        zoom: 9,
      })
      this.map.addControl(
        new maplibregl.NavigationControl({ showCompass: false }),
        "top-right",
      )
      this.map.on("load", () => this.loadHexagons())
    } catch (error) {
      console.error("Error initializing map:", error)
      this.hideLoadingOverlay()
    }
  }

  styleName() {
    return document.documentElement.dataset.theme === "dawarich"
      ? "light"
      : "dark"
  }

  async loadHexagons() {
    try {
      const dataBounds = this.dataBoundsValue

      if (dataBounds && dataBounds.point_count > 0) {
        this.map.fitBounds(
          [
            [dataBounds.min_lng, dataBounds.min_lat],
            [dataBounds.max_lng, dataBounds.max_lat],
          ],
          { padding: 20, duration: 0 },
        )
        await new Promise((resolve) => {
          this.map.once("moveend", resolve)
          setTimeout(resolve, 1000)
        })
      }

      if (
        dataBounds &&
        dataBounds.point_count > 0 &&
        this.hexagonsAvailableValue
      ) {
        await this.loadStaticHexagons()
      } else {
        this.hideLoadingOverlay()
      }
    } catch (error) {
      console.error("Error initializing hexagon grid:", error)
      this.hideLoadingOverlay()
    }
  }

  async loadStaticHexagons() {
    this.showLoadingOverlay()
    this.setInteractions(false)

    try {
      const startDate = new Date(this.yearValue, this.monthValue - 1, 1)
      const endDate = new Date(this.yearValue, this.monthValue, 0, 23, 59, 59)
      const dataBounds = this.dataBoundsValue

      const params = new URLSearchParams({
        min_lon: dataBounds.min_lng,
        min_lat: dataBounds.min_lat,
        max_lon: dataBounds.max_lng,
        max_lat: dataBounds.max_lat,
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString(),
        uuid: this.uuidValue,
      })

      const response = await fetch(`/api/v1/maps/hexagons?${params}`, {
        headers: { "Content-Type": "application/json" },
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const geojsonData = await response.json()
      if (geojsonData.features && geojsonData.features.length > 0) {
        this.addHexagonLayers(geojsonData)
      }
    } catch (error) {
      console.error("Failed to load static hexagons:", error)
    } finally {
      this.setInteractions(true)
      this.hideLoadingOverlay()
    }
  }

  addHexagonLayers(geojsonData) {
    const existing = this.map.getSource("hexagons")
    if (existing) {
      existing.setData(geojsonData)
      return
    }

    this.map.addSource("hexagons", {
      type: "geojson",
      data: geojsonData,
      generateId: true,
    })
    this.map.addLayer({
      id: "hexagons-fill",
      type: "fill",
      source: "hexagons",
      paint: {
        "fill-color": "#3388ff",
        "fill-opacity": [
          "case",
          ["boolean", ["feature-state", "hover"], false],
          0.8,
          0.3,
        ],
      },
    })
    this.map.addLayer({
      id: "hexagons-line",
      type: "line",
      source: "hexagons",
      paint: {
        "line-color": "#3388ff",
        "line-width": [
          "case",
          ["boolean", ["feature-state", "hover"], false],
          2,
          1,
        ],
        "line-opacity": [
          "case",
          ["boolean", ["feature-state", "hover"], false],
          1,
          0.3,
        ],
      },
    })

    this.map.on("click", "hexagons-fill", (event) => this.openPopup(event))
    this.map.on("mousemove", "hexagons-fill", (event) =>
      this.handleHover(event),
    )
    this.map.on("mouseleave", "hexagons-fill", () => this.clearHover())
  }

  openPopup(event) {
    const feature = event.features?.[0]
    if (!feature) return

    new maplibregl.Popup({ maxWidth: "320px" })
      .setLngLat(event.lngLat)
      .setHTML(buildHexagonPopup(feature.properties, this.timezoneValue))
      .addTo(this.map)
  }

  handleHover(event) {
    const feature = event.features?.[0]
    if (!feature) return

    this.map.getCanvas().style.cursor = "pointer"
    if (this.hoveredId !== null && this.hoveredId !== feature.id) {
      this.map.setFeatureState(
        { source: "hexagons", id: this.hoveredId },
        { hover: false },
      )
    }
    this.hoveredId = feature.id
    this.map.setFeatureState(
      { source: "hexagons", id: feature.id },
      { hover: true },
    )
  }

  clearHover() {
    this.map.getCanvas().style.cursor = ""
    if (this.hoveredId !== null) {
      this.map.setFeatureState(
        { source: "hexagons", id: this.hoveredId },
        { hover: false },
      )
      this.hoveredId = null
    }
  }

  setInteractions(enabled) {
    const handlers = [
      this.map.dragPan,
      this.map.scrollZoom,
      this.map.doubleClickZoom,
      this.map.touchZoomRotate,
      this.map.boxZoom,
      this.map.keyboard,
    ]
    for (const handler of handlers) {
      if (enabled) {
        handler.enable()
      } else {
        handler.disable()
      }
    }
  }

  showLoadingOverlay() {
    const loadingElement = document.getElementById("map-loading")
    if (loadingElement) {
      loadingElement.style.display = "flex"
      loadingElement.style.visibility = "visible"
      loadingElement.style.zIndex = "9999"
    }
  }

  hideLoadingOverlay() {
    const loadingElement = document.getElementById("map-loading")
    if (loadingElement) {
      loadingElement.style.display = "none"
    }
  }
}
