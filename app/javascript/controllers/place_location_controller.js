import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import * as maplibregl from "maplibre-gl"

export default class extends Controller {
  static targets = ["map", "latitude", "longitude"]
  static values = {
    latitude: Number,
    longitude: Number,
    editable: Boolean,
    tilesUrl: String,
    tilesFallback: Boolean,
  }

  async connect() {
    this.disposed = false
    const center = [this.longitudeValue, this.latitudeValue]
    const map = await MapInitializer.initialize(this.mapTarget, {
      center,
      zoom: this.latitudeValue || this.longitudeValue ? 14 : 2,
      vectorTilesUrl: this.tilesUrlValue || null,
      tilesFallback: this.tilesFallbackValue,
    })
    if (this.disposed) {
      map.remove()
      return
    }
    this.map = map
    this.marker = new maplibregl.Marker({ draggable: this.editableValue })
      .setLngLat(center)
      .addTo(map)
    if (this.editableValue) {
      map.on("click", (event) => this.setCoordinates(event.lngLat))
      this.marker.on("dragend", () =>
        this.setCoordinates(this.marker.getLngLat()),
      )
    }
  }

  setCoordinates({ lat, lng }) {
    this.latitudeTarget.value = lat.toFixed(6)
    this.longitudeTarget.value = lng.toFixed(6)
    this.marker.setLngLat([lng, lat])
    for (const field of [this.latitudeTarget, this.longitudeTarget]) {
      field.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  coordinatesChanged() {
    if (!this.map) return
    const lat = Number(this.latitudeTarget.value)
    const lng = Number(this.longitudeTarget.value)
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lng) ||
      Math.abs(lat) > 90 ||
      Math.abs(lng) > 180
    )
      return
    this.marker.setLngLat([lng, lat])
    this.map.easeTo({ center: [lng, lat], zoom: 14 })
  }

  disconnect() {
    this.disposed = true
    this.marker?.remove()
    this.map?.remove()
  }
}
