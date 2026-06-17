import maplibregl from "maplibre-gl"
import { arcifyFlights } from "../utils/flight_arcs"
import { escapeHtml } from "../utils/geojson_transformers"
import { BaseLayer } from "./base_layer"

/**
 * Flights layer: AirTrail flights drawn as arcs between departure and arrival
 * airports. Styling respects the saved MapLibre style (light/dark) passed in
 * via options, not the DOM dark-mode class.
 */
export class FlightsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "flights", ...options })
    this.popup = new maplibregl.Popup({
      closeButton: true,
      closeOnClick: true,
      className: "flights-popup",
    })
    this._onClick = this._onClick.bind(this)
  }

  lineColor() {
    return "#6366F1"
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "line",
        source: this.sourceId,
        layout: { "line-join": "round", "line-cap": "round" },
        paint: {
          "line-color": [
            "case",
            ["has", "color"],
            ["get", "color"],
            this.lineColor(),
          ],
          "line-width": 4,
          "line-opacity": 0.7,
        },
      },
    ]
  }

  add(data) {
    super.add(arcifyFlights(data))
    this.map.on("click", this.id, this._onClick)
    this.map.on("mouseenter", this.id, this._setPointer)
    this.map.on("mouseleave", this.id, this._unsetPointer)
  }

  update(data) {
    super.update(arcifyFlights(data))
  }

  remove() {
    this.map.off("click", this.id, this._onClick)
    this.map.off("mouseenter", this.id, this._setPointer)
    this.map.off("mouseleave", this.id, this._unsetPointer)
    super.remove()
  }

  _setPointer = () => {
    this.map.getCanvas().style.cursor = "pointer"
  }

  _unsetPointer = () => {
    this.map.getCanvas().style.cursor = ""
  }

  _onClick(event) {
    const feature = event.features?.[0]
    if (!feature) return

    const p = feature.properties || {}
    const route = [p.from_code, p.to_code]
      .filter(Boolean)
      .map(escapeHtml)
      .join(" → ")
    const airline = p.airline_name
      ? `<div>${escapeHtml(p.airline_name)}</div>`
      : ""
    const number = p.flight_number ? ` ${escapeHtml(p.flight_number)}` : ""
    const date = p.flight_date ? `<div>${escapeHtml(p.flight_date)}</div>` : ""
    const seat = p.seat ? `<div>Seat: ${escapeHtml(p.seat)}</div>` : ""

    const html = `
      <div class="text-sm">
        <strong>${route}${number}</strong>
        ${airline}${date}${seat}
      </div>
    `

    this.popup.setLngLat(event.lngLat).setHTML(html).addTo(this.map)
  }
}
