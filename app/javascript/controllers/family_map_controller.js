import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { escapeHtml } from "maps_maplibre/utils/geojson_transformers"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

const MEMBER_COLORS = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
]

export default class extends Controller {
  static targets = ["map"]
  static values = { locations: Array }

  connect() {
    if (this.locationsValue.length === 0) return

    requestAnimationFrame(() => this.initMap())
  }

  disconnect() {
    if (this._initTimer) {
      clearTimeout(this._initTimer)
      this._initTimer = null
    }
    if (this._popup) {
      this._popup.remove()
      this._popup = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async initMap() {
    try {
      const container = this.mapTarget
      if (!container || container.clientHeight < 50) {
        this._initRetries = (this._initRetries || 0) + 1
        if (this._initRetries < 25) {
          this._initTimer = setTimeout(() => this.initMap(), 200)
        }
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
        zoom: 2,
        attributionControl: false,
      })

      this.map.addControl(new maplibregl.NavigationControl(), "top-right")
      this.map.on("load", () => this.addMembers())
    } catch (error) {
      console.error("Family map init failed:", error)
    }
  }

  addMembers() {
    const locations = this.locationsValue
    if (!locations.length) return

    const features = locations.map((loc, i) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [loc.longitude, loc.latitude],
      },
      properties: {
        id: loc.user_id,
        name: loc.email || "Unknown",
        color: MEMBER_COLORS[i % MEMBER_COLORS.length],
        lastUpdate: loc.timestamp,
      },
    }))

    const geojson = { type: "FeatureCollection", features }

    this.map.addSource("family-members", { type: "geojson", data: geojson })

    // Pulse ring
    this.map.addLayer({
      id: "family-pulse",
      type: "circle",
      source: "family-members",
      paint: {
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 8, 16, 15, 26],
        "circle-color": ["get", "color"],
        "circle-opacity": 0.15,
      },
    })

    // Main circle
    this.map.addLayer({
      id: "family-circles",
      type: "circle",
      source: "family-members",
      paint: {
        "circle-radius": 10,
        "circle-color": ["get", "color"],
        "circle-stroke-width": 2,
        "circle-stroke-color": "#ffffff",
        "circle-opacity": 0.9,
      },
    })

    // Email labels
    this.map.addLayer({
      id: "family-labels",
      type: "symbol",
      source: "family-members",
      layout: {
        "text-field": ["get", "name"],
        "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
        "text-size": 12,
        "text-offset": [0, 1.5],
        "text-anchor": "top",
      },
      paint: {
        "text-color": document.documentElement
          .getAttribute("data-theme")
          ?.includes("dark")
          ? "#e5e7eb"
          : "#111827",
        "text-halo-color": document.documentElement
          .getAttribute("data-theme")
          ?.includes("dark")
          ? "#1f2937"
          : "#ffffff",
        "text-halo-width": 2,
      },
    })

    // Click to show popup
    this.map.on("click", "family-circles", (e) => {
      const props = e.features[0].properties
      const coords = e.features[0].geometry.coordinates.slice()

      if (this._popup) this._popup.remove()
      this._popup = new maplibregl.Popup({ offset: 16, closeButton: false })
        .setLngLat(coords)
        .setHTML(
          `<div style="font-size:13px;line-height:1.5">
            <div style="font-weight:600">${escapeHtml(props.name)}</div>
            <div style="opacity:0.6;font-size:11px">${escapeHtml(this.timeAgo(props.lastUpdate))}</div>
          </div>`,
        )
        .addTo(this.map)
    })

    this.map.on("mouseenter", "family-circles", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "family-circles", () => {
      this.map.getCanvas().style.cursor = ""
    })

    // Fit bounds
    const bounds = new maplibregl.LngLatBounds()
    for (const l of locations) bounds.extend([l.longitude, l.latitude])
    this.map.fitBounds(bounds, { padding: 60, maxZoom: 14 })
  }

  flyToMember(event) {
    if (!this.map || !this.map.loaded()) return

    const row = event.currentTarget
    const lon = parseFloat(row.dataset.lon)
    const lat = parseFloat(row.dataset.lat)
    if (Number.isNaN(lon) || Number.isNaN(lat)) return

    this.map.flyTo({
      center: [lon, lat],
      zoom: 15,
      duration: 1000,
    })
  }

  timeAgo(timestamp) {
    const seconds = Math.floor(Date.now() / 1000 - timestamp)
    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    return `${Math.floor(seconds / 86400)}d ago`
  }
}
