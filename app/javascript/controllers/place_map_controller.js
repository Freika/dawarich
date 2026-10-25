import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { getCurrentTheme } from "maps_maplibre/utils/popup_theme"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    name: String,
  }

  connect() {
    this.initializeMap()
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async initializeMap() {
    try {
      const style = await getMapStyle(getCurrentTheme())

      if (this.map) return

      this.map = new maplibregl.Map({
        container: this.element,
        style,
        center: [this.lngValue, this.latValue],
        zoom: 14,
        attributionControl: false,
      })

      this.map.addControl(
        new maplibregl.NavigationControl({ showCompass: false }),
        "top-right",
      )

      this.map.on("load", () => this.addMarker())
    } catch (error) {
      console.error("Error initializing place map:", error)
    }
  }

  addMarker() {
    // Create a custom marker element
    const el = document.createElement("div")
    el.className = "place-map-marker"
    el.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#ef4444" class="w-8 h-8 drop-shadow-lg">
        <path fill-rule="evenodd" d="m11.54 22.351.07.04.028.016a.76.76 0 0 0 .723 0l.028-.015.071-.041a16.975 16.975 0 0 0 1.144-.742 19.58 19.58 0 0 0 2.683-2.282c1.944-1.99 3.963-4.98 3.963-8.827a8.25 8.25 0 0 0-16.5 0c0 3.846 2.02 6.837 3.963 8.827a19.58 19.58 0 0 0 2.682 2.282 16.975 16.975 0 0 0 1.145.742Z" clip-rule="evenodd" />
      </svg>`

    new maplibregl.Marker({ element: el })
      .setLngLat([this.lngValue, this.latValue])
      .setPopup(
        new maplibregl.Popup({ offset: 25 }).setHTML(
          `<strong>${escapeHtml(this.nameValue)}</strong><br/>${this.latValue.toFixed(6)}, ${this.lngValue.toFixed(6)}`,
        ),
      )
      .addTo(this.map)
  }
}

function escapeHtml(str) {
  const div = document.createElement("div")
  div.textContent = str
  return div.innerHTML
}
