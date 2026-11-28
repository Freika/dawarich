import { formatDateTime } from "i18n"
import * as maplibregl from "maplibre-gl"
import { escapeHtml } from "../utils/geojson_transformers"
import { BaseLayer } from "./base_layer"

/**
 * Recent point layer for displaying the user's most recent location
 * Seeded on page load and moved by live mode, regardless of points layer visibility
 */
export class RecentPointLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "recent-point", visible: true, ...options })
    this.hoverTitle = options.hoverTitle
    this._popup = new maplibregl.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 12,
    })
    this._onEnter = (e) => this._showPopup(e)
    this._onLeave = () => this._hidePopup()
    this._onClick = (e) => {
      const features = this.map.getLayer(this.id)
        ? this.map.queryRenderedFeatures(e.point, { layers: [this.id] })
        : []
      if (features.length) this._showPopup({ lngLat: e.lngLat, features })
      else this._hidePopup()
    }
  }

  add(data, beforeId) {
    super.add(data, beforeId)
    if (!this.hoverTitle) return
    this.map.on("mouseenter", this.id, this._onEnter)
    this.map.on("mouseleave", this.id, this._onLeave)
    this.map.on("click", this._onClick)
  }

  remove() {
    if (this.hoverTitle) {
      this.map.off("mouseenter", this.id, this._onEnter)
      this.map.off("mouseleave", this.id, this._onLeave)
      this.map.off("click", this._onClick)
    }
    this._hidePopup()
    super.remove()
  }

  _showPopup(e) {
    const timestamp = Number(e.features?.[0]?.properties?.timestamp)
    const time = timestamp
      ? `<div style="font-size:12px;opacity:0.8">${escapeHtml(formatDateTime(timestamp * 1000))}</div>`
      : ""
    this.map.getCanvas().style.cursor = "pointer"
    this._popup
      .setLngLat(e.lngLat)
      .setHTML(
        `<div style="font-weight:600">${escapeHtml(this.hoverTitle)}</div>${time}`,
      )
      .addTo(this.map)
  }

  _hidePopup() {
    this.map.getCanvas().style.cursor = ""
    this._popup.remove()
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  getLayerConfigs() {
    return [
      // Pulsing outer circle (animation effect)
      {
        id: `${this.id}-pulse`,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#ef4444",
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 8, 20, 40],
          "circle-opacity": 0.3,
        },
      },
      // Main point circle
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#ef4444",
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 6, 20, 20],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  /**
   * Update layer with a single recent point
   * @param {number} lon - Longitude
   * @param {number} lat - Latitude
   * @param {Object} properties - Additional point properties
   */
  updateRecentPoint(lon, lat, properties = {}) {
    const data = {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [lon, lat],
          },
          properties,
        },
      ],
    }
    this.update(data)
  }

  /**
   * Clear the recent point
   */
  clear() {
    this.update({
      type: "FeatureCollection",
      features: [],
    })
  }
}
