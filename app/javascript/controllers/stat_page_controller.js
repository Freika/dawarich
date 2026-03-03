import L from "leaflet"
import "leaflet.heat"
import { createAllMapLayers } from "../maps/layers"
import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["map", "loading", "heatmapBtn", "pointsBtn"]

  connect() {
    super.connect()
    console.log("StatPage controller connected")

    // Get data attributes from the element (will be passed from the view)
    this.year = parseInt(
      this.element.dataset.year || new Date().getFullYear(),
      10,
    )
    this.month = parseInt(
      this.element.dataset.month || new Date().getMonth() + 1,
      10,
    )
    this.apiKey = this.element.dataset.apiKey
    this.selfHosted = this.element.dataset.selfHosted || this.selfHostedValue

    console.log(
      `Loading data for ${this.month}/${this.year} with API key: ${this.apiKey ? "present" : "missing"}`,
    )

    // Initialize map after a short delay to ensure container is ready
    setTimeout(() => {
      this.initializeMap()
    }, 100)
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
    }
    console.log("StatPage controller disconnected")
  }

  initializeMap() {
    if (!this.mapTarget) {
      console.error("Map target not found")
      return
    }

    try {
      // Initialize Leaflet map
      this.map = L.map(this.mapTarget, {
        zoomControl: true,
        scrollWheelZoom: true,
        doubleClickZoom: true,
        boxZoom: false,
        keyboard: false,
        dragging: true,
        touchZoom: true,
      }).setView([52.520008, 13.404954], 10) // Default to Berlin

      // Add dynamic tile layer based on self-hosted setting
      this.addMapLayers()

      // Add small scale control
      L.control
        .scale({
          position: "bottomright",
          maxWidth: 100,
          imperial: true,
          metric: true,
        })
        .addTo(this.map)

      // Initialize layers
      this.markersLayer = L.layerGroup() // Don't add to map initially
      this.heatmapLayer = null

      // Load data for this month
      this.loadMonthData()
    } catch (error) {
      console.error("Error initializing map:", error)
      this.showError("Failed to initialize map")
    }
  }

  async loadMonthData() {
    try {
      // Show loading
      this.showLoading(true)

      // Calculate date range for the month
      const startDate = `${this.year}-${this.month.toString().padStart(2, "0")}-01T00:00:00`
      const lastDay = new Date(this.year, this.month, 0).getDate()
      const endDate = `${this.year}-${this.month.toString().padStart(2, "0")}-${lastDay}T23:59:59`

      console.log(`Fetching points from ${startDate} to ${endDate}`)

      // Fetch points data for the month using Authorization header
      const response = await fetch(
        `/api/v1/points?start_at=${encodeURIComponent(startDate)}&end_at=${encodeURIComponent(endDate)}&per_page=1000`,
        {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.apiKey}`,
          },
        },
      )

      if (!response.ok) {
        console.error(`API request failed with status: ${response.status}`)
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      console.log(
        `Received ${Array.isArray(data) ? data.length : 0} points from API`,
      )

      if (Array.isArray(data) && data.length > 0) {
        this.processPointsData(data)
      } else {
        console.log("No points data available for this month")
        this.showNoData()
      }
    } catch (error) {
      console.error("Error loading month data:", error)
      this.showError("Failed to load location data")
      // Don't fallback to mock data - show the error instead
    } finally {
      this.showLoading(false)
    }
  }

  processPointsData(points) {
    console.log(
      `Processing ${points.length} points for ${this.month}/${this.year}`,
    )

    // Clear existing markers
    this.markersLayer.clearLayers()

    // Convert points to markers (API returns latitude/longitude as strings)
    const markers = points.map((point) => {
      const lat = parseFloat(point.latitude)
      const lng = parseFloat(point.longitude)

      return L.circleMarker([lat, lng], {
        radius: 3,
        fillColor: "#570df8",
        color: "#570df8",
        weight: 1,
        opacity: 0.8,
        fillOpacity: 0.6,
      })
    })

    // Add markers to layer (but don't add to map yet)
    markers.forEach((marker) => {
      this.markersLayer.addLayer(marker)
    })

    // Prepare data for heatmap (convert strings to numbers)
    this.heatmapData = points.map((point) => [
      parseFloat(point.latitude),
      parseFloat(point.longitude),
      0.5,
    ])

    // Show heatmap by default
    if (this.heatmapData.length > 0) {
      this.heatmapLayer = L.heatLayer(this.heatmapData, {
        radius: 25,
        blur: 15,
        maxZoom: 17,
        max: 1.0,
      }).addTo(this.map)

      // Set button states
      this.heatmapBtnTarget.classList.add("btn-active")
      this.pointsBtnTarget.classList.remove("btn-active")
    }

    // Fit map to show all points
    if (points.length > 0) {
      const group = new L.featureGroup(markers)
      this.map.fitBounds(group.getBounds().pad(0.1))
    }

    console.log("Points processed successfully")
  }

  toggleHeatmap() {
    if (!this.heatmapData || this.heatmapData.length === 0) {
      console.warn("No heatmap data available")
      return
    }

    if (this.heatmapLayer && this.map.hasLayer(this.heatmapLayer)) {
      // Remove heatmap
      this.map.removeLayer(this.heatmapLayer)
      this.heatmapLayer = null
      this.heatmapBtnTarget.classList.remove("btn-active")

      // Show points
      if (!this.map.hasLayer(this.markersLayer)) {
        this.map.addLayer(this.markersLayer)
        this.pointsBtnTarget.classList.add("btn-active")
      }
    } else {
      // Add heatmap
      this.heatmapLayer = L.heatLayer(this.heatmapData, {
        radius: 25,
        blur: 15,
        maxZoom: 17,
        max: 1.0,
      }).addTo(this.map)

      this.heatmapBtnTarget.classList.add("btn-active")

      // Hide points
      if (this.map.hasLayer(this.markersLayer)) {
        this.map.removeLayer(this.markersLayer)
        this.pointsBtnTarget.classList.remove("btn-active")
      }
    }
  }

  togglePoints() {
    if (this.map.hasLayer(this.markersLayer)) {
      // Remove points
      this.map.removeLayer(this.markersLayer)
      this.pointsBtnTarget.classList.remove("btn-active")
    } else {
      // Add points
      this.map.addLayer(this.markersLayer)
      this.pointsBtnTarget.classList.add("btn-active")

      // Remove heatmap if active
      if (this.heatmapLayer && this.map.hasLayer(this.heatmapLayer)) {
        this.map.removeLayer(this.heatmapLayer)
        this.heatmapBtnTarget.classList.remove("btn-active")
      }
    }
  }

  showLoading(show) {
    if (this.hasLoadingTarget) {
      this.loadingTarget.style.display = show ? "flex" : "none"
    }
  }

  showError(message) {
    console.error(message)
    if (this.hasLoadingTarget) {
      this.loadingTarget.innerHTML = `
        <div class="alert alert-error">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
          <span>${message}</span>
        </div>
      `
      this.loadingTarget.style.display = "flex"
    }
  }

  showNoData() {
    console.log("No data available for this month")
    if (this.hasLoadingTarget) {
      this.loadingTarget.innerHTML = `
        <div class="alert alert-info">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
          <span>No location data available for ${new Date(this.year, this.month - 1).toLocaleDateString("en-US", { month: "long", year: "numeric" })}</span>
        </div>
      `
      this.loadingTarget.style.display = "flex"
    }
  }

  addMapLayers() {
    try {
      // Use appropriate default layer based on self-hosted mode
      const selectedLayerName =
        this.selfHosted === "true" ? "OpenStreetMap" : "Light"
      const maps = createAllMapLayers(
        this.map,
        selectedLayerName,
        this.selfHosted,
        "dark",
      )

      // If no layers were created, fall back to OSM
      if (Object.keys(maps).length === 0) {
        console.warn("No map layers available, falling back to OSM")
        this.addFallbackOSMLayer()
      }
    } catch (error) {
      console.error("Error creating map layers:", error)
      console.log("Falling back to OSM tile layer")
      this.addFallbackOSMLayer()
    }
  }

  addFallbackOSMLayer() {
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap contributors",
    }).addTo(this.map)
  }
}
