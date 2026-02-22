import BaseController from "./base_controller"
import L from "leaflet"
import Flash from "./flash_controller"

export default class extends BaseController {
  static targets = ["urlInput", "mapContainer", "saveButton"]

  DEFAULT_TILE_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'

  connect() {
    console.log("Controller connected!")
    // Wait for the next frame to ensure the DOM is ready
    requestAnimationFrame(() => {
      // Force container height
      this.mapContainerTarget.style.height = '500px'
      this.initializeMap()
    })
  }

  initializeMap() {
    console.log("Initializing map...")
    if (!this.map) {
      this.map = L.map(this.mapContainerTarget).setView([51.505, -0.09], 13)
      // Invalidate size after initialization
      setTimeout(() => {
        this.map.invalidateSize()
      }, 0)
      this.updatePreview()
    }
  }

  updatePreview() {
    console.log("Updating preview...")
    const url = this.urlInputTarget.value || this.DEFAULT_TILE_URL

    // Only animate if save button target exists
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.classList.add('btn-animate')
      setTimeout(() => {
        this.saveButtonTarget.classList.remove('btn-animate')
      }, 1000)
    }

    if (this.currentLayer) {
      this.map.removeLayer(this.currentLayer)
    }

    try {
      this.currentLayer = L.tileLayer(url, {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(this.map)
    } catch (e) {
      console.error('Invalid tile URL:', e)
      Flash.show('error', 'Invalid tile URL. Reverting to OpenStreetMap.')

      // Reset input to default OSM URL
      this.urlInputTarget.value = this.DEFAULT_TILE_URL

      // Create default layer
      this.currentLayer = L.tileLayer(this.DEFAULT_TILE_URL, {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(this.map)
    }
  }
}
