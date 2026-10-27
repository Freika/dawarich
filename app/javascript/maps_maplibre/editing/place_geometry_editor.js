import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import {
  radiusCircle,
  radiusFromHandle,
  radiusHandle,
} from "maps_maplibre/editing/place_editor_state"

export class PlaceGeometryEditor {
  constructor(map) {
    this.map = map
  }

  start(place, maximum) {
    this.stop()
    this.place = { ...place }
    this.maximum = maximum
    const center = [place.longitude, place.latitude]
    this.map.addSource("place-edit-radius", {
      type: "geojson",
      data: this.circle(),
    })
    this.map.addLayer({
      id: "place-edit-fill",
      type: "fill",
      source: "place-edit-radius",
      paint: { "fill-color": "#2563eb", "fill-opacity": 0.15 },
    })
    this.map.addLayer({
      id: "place-edit-line",
      type: "line",
      source: "place-edit-radius",
      paint: { "line-color": "#2563eb", "line-width": 2 },
    })
    this.pin = this.marker(
      "place-edit-pin",
      translate("places.move_pin"),
      "●",
      center,
    )
    this.handle = this.marker(
      "place-edit-handle",
      translate("places.resize_radius"),
      "↔",
      radiusHandle(center, place.visit_radius),
    )
    this.pin.on("drag", () => {
      const { lng, lat } = this.pin.getLngLat()
      this.place.longitude = ((lng + 540) % 360) - 180
      this.place.latitude = lat
      this.handle.setLngLat(
        radiusHandle([this.place.longitude, lat], this.place.visit_radius),
      )
      this.changed()
    })
    this.handle.on("drag", () => {
      const { lng, lat } = this.handle.getLngLat()
      this.place.visit_radius = radiusFromHandle(
        [this.place.longitude, this.place.latitude],
        [lng, lat],
        this.maximum,
      )
      this.changed()
    })
    this.handle.on("dragend", () => {
      this.handle.setLngLat(
        radiusHandle(
          [this.place.longitude, this.place.latitude],
          this.place.visit_radius,
        ),
      )
    })
    const ring = this.circle().geometry.coordinates[0]
    const bounds = ring.reduce(
      (bounds, point) => bounds.extend(point),
      new maplibregl.LngLatBounds(center, center),
    )
    const mobile = this.map.getContainer().clientWidth < 768
    this.map.fitBounds(bounds, {
      padding: mobile
        ? { top: 60, right: 60, bottom: 240, left: 60 }
        : { top: 80, right: 480, bottom: 80, left: 80 },
      maxZoom: 17,
      duration: 300,
    })
    this.changed()
  }

  marker(id, label, glyph, position) {
    const element = document.createElement("button")
    element.type = "button"
    element.className = "place-edit-marker"
    element.dataset.testid = id
    element.setAttribute("aria-label", label)
    element.title = label
    element.textContent = glyph
    return new maplibregl.Marker({ element, draggable: true })
      .setLngLat(position)
      .addTo(this.map)
  }

  circle() {
    return {
      type: "Feature",
      properties: {},
      geometry: {
        type: "Polygon",
        coordinates: [
          radiusCircle(
            [this.place.longitude, this.place.latitude],
            this.place.visit_radius,
          ),
        ],
      },
    }
  }

  changed() {
    this.map.getSource("place-edit-radius").setData(this.circle())
    document.dispatchEvent(
      new CustomEvent("place:geometry-changed", { detail: { ...this.place } }),
    )
  }

  stop() {
    this.pin?.remove()
    this.handle?.remove()
    this.pin = null
    this.handle = null
    for (const id of ["place-edit-fill", "place-edit-line"]) {
      if (this.map.getLayer(id)) this.map.removeLayer(id)
    }
    if (this.map.getSource("place-edit-radius"))
      this.map.removeSource("place-edit-radius")
    this.place = null
  }
}
