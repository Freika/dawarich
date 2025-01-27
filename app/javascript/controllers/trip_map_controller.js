// This controller is being used on:
// - trips/index

import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static values = {
    tripId: Number,
    path: String,
    apiKey: String,
    userSettings: Object,
    timezone: String,
    distanceUnit: String
  }

  connect() {
    console.log("TripMap controller connected")

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
      attributionControl: true
    })

    // Add the tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: "&copy; <a href='http://www.openstreetmap.org/copyright'>OpenStreetMap</a>"
    }).addTo(this.map)

    // If we have coordinates, show the route
    if (this.hasPathValue && this.pathValue) {
      this.showRoute()
    } else {
      console.log("No path value available")
    }
  }

  showRoute() {
    const points = this.parseLineString(this.pathValue)

    // Only create polyline if we have points
    if (points.length > 0) {
      const polyline = L.polyline(points, {
        color: 'blue',
        opacity: 0.8,
        weight: 3,
        zIndexOffset: 400
      })

      // Add the polyline to the map
      polyline.addTo(this.map)

      // Fit the map bounds
      this.map.fitBounds(polyline.getBounds(), {
        padding: [20, 20]
      })
    } else {
      console.error("No valid points to create polyline")
    }
  }

  parseLineString(linestring) {
    try {
      // Remove 'LINESTRING (' from start and ')' from end
      const coordsString = linestring
        .replace(/LINESTRING\s*\(/, '')  // Remove LINESTRING and opening parenthesis
        .replace(/\)$/, '')              // Remove closing parenthesis
        .trim()                          // Remove any leading/trailing whitespace

      // Split into coordinate pairs and parse
      const points = coordsString.split(',').map(pair => {
        // Clean up any extra whitespace and remove any special characters
        const cleanPair = pair.trim().replace(/[()"\s]+/g, ' ')
        const [lng, lat] = cleanPair.split(' ').filter(Boolean).map(Number)

        // Validate the coordinates
        if (isNaN(lat) || isNaN(lng) || !lat || !lng) {
          console.error("Invalid coordinates:", cleanPair)
          return null
        }

        return [lat, lng] // Leaflet uses [lat, lng] order
      }).filter(point => point !== null) // Remove any invalid points

      // Validate we have points before returning
      if (points.length === 0) {
        return []
      }

      return points
    } catch (error) {
      return []
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
    }
  }
}
