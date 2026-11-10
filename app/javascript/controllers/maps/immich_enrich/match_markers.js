import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"

/**
 * Map markers for the scanned photo matches.
 * Mixed into the controller; `this` is the controller.
 */
export const matchMarkers = {
  addMarkers() {
    const map = this.getMap()
    if (!map) return

    this.markerElements = []

    this.matches.forEach((match, index) => {
      const el = this.buildMarkerElement(match, index, true)

      el.addEventListener("click", (e) => {
        e.stopPropagation()
        const mapRef = this.getMap()
        if (mapRef) {
          mapRef.flyTo({
            center: [match.longitude, match.latitude],
            zoom: 15,
          })
        }
        this.matchListTarget
          .querySelectorAll("[data-index]")
          .forEach((item) => {
            item.classList.remove("ring-2", "ring-primary")
          })
        const listItem = this.matchListTarget.querySelector(
          `[data-index="${index}"]`,
        )
        if (listItem) {
          listItem.classList.add("ring-2", "ring-primary")
          listItem.scrollIntoView({ behavior: "smooth", block: "nearest" })
        }
      })

      const marker = new maplibregl.Marker({ element: el, draggable: true })
        .setLngLat([match.longitude, match.latitude])
        .addTo(map)

      marker.on("dragend", () => {
        const lngLat = marker.getLngLat()
        const listItem = this.matchListTarget.querySelector(
          `[data-index="${index}"]`,
        )
        if (listItem) {
          const coordEl = listItem.querySelector("[data-coord]")
          if (coordEl) {
            coordEl.textContent = `${lngLat.lat.toFixed(4)}, ${lngLat.lng.toFixed(4)}`
          }
        }
      })

      this.markers[index] = marker
      this.markerElements[index] = el
    })

    if (this.matches.length > 0) {
      const bounds = new maplibregl.LngLatBounds()
      for (const m of this.matches) {
        bounds.extend([m.longitude, m.latitude])
      }
      map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
    }
  },

  buildMarkerElement(match, _index, selected) {
    const el = document.createElement("div")
    el.className = "immich-enrich-marker"
    this.applyMarkerStyle(el, match, selected, true)
    el.title = translate("immich.marker_title", {
      filename: match.filename,
      delta: this.formatTimeDelta(match.time_delta_seconds),
    })
    return el
  },

  applyMarkerStyle(el, match, selected, initial = false) {
    const color = selected
      ? this.confidenceColor(match.time_delta_seconds)
      : "#9ca3af"
    const icon = selected ? "📷✓" : "📷"

    if (initial) {
      el.style.cssText = `
        width: 32px; height: 32px; border-radius: 50%;
        background: ${color}; border: 2px solid white;
        box-shadow: 0 2px 6px rgba(0,0,0,0.3);
        cursor: grab; display: flex; align-items: center; justify-content: center;
        font-size: 12px; pointer-events: auto; z-index: 10;
      `
    } else {
      el.style.background = color
      el.style.border = selected ? "2px solid white" : "2px dashed #6b7280"
      el.style.opacity = selected ? "1" : "0.6"
    }
    el.textContent = icon
  },

  updateMarkerStyle(index, selected) {
    const el = this.markerElements?.[index]
    const match = this.matches[index]
    if (el && match) {
      this.applyMarkerStyle(el, match, selected)
    }
  },

  updateAllMarkerStyles() {
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]")
      .forEach((cb) => {
        const index = parseInt(cb.dataset.index, 10)
        this.updateMarkerStyle(index, cb.checked)
      })
  },

  removeMarkers() {
    this.markers.forEach((marker) => {
      if (marker) marker.remove()
    })
    this.markers = []
    this.markerElements = []
  },

  // --- UI state ---
}
