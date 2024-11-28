import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static values = {
    tripId: Number,
    coordinates: Array,
    apiKey: String,
    userSettings: Object,
    timezone: String,
    distanceUnit: String
  }

  connect() {
    setTimeout(() => {
      this.initializeMap()
    }, 100)
  }

  initializeMap() {
    // Initialize map with basic configuration
    this.map = L.map(this.element, {
      zoomControl: false,
      dragging: false,
      scrollWheelZoom: false,
      attributionControl: true  // Disable default attribution control
    })

    // Add the tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: "&copy; <a href='http://www.openstreetmap.org/copyright'>OpenStreetMap</a>"
    }).addTo(this.map)

    // If we have coordinates, show the route
    if (this.hasCoordinatesValue && this.coordinatesValue.length > 0) {
      this.showRoute()
    }
  }

  showRoute() {
    const points = this.coordinatesValue.map(coord => [coord[0], coord[1]])

    const polyline = L.polyline(points, {
      color: 'blue',
      weight: 3,
      opacity: 0.8
    }).addTo(this.map)

    this.map.fitBounds(polyline.getBounds(), {
      padding: [20, 20]
    })
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
    }
  }
}
