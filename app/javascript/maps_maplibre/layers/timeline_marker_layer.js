import maplibregl from "maplibre-gl"
import { BaseLayer } from "./base_layer"

/**
 * Timeline marker layer for displaying a pulsing marker at timeline position
 * Supports both circle markers (default) and transportation mode emojis
 * Uses an HTML marker for emoji rendering (MapLibre SDF fonts can't render emoji)
 * Uses orange color to distinguish from recent point (red)
 */
export class TimelineMarkerLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "timeline-marker", visible: false, ...options })
    this._currentEmoji = null
    this._htmlMarker = null
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
      // Pulsing outer circle (always visible as background)
      {
        id: `${this.id}-pulse`,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#f97316", // Orange
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 10, 20, 50],
          "circle-opacity": 0.3,
        },
      },
      // Main point circle (visible when no emoji)
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#f97316", // Orange
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 8, 20, 24],
          "circle-stroke-width": 3,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  /**
   * Show marker at specified coordinates
   * @param {number} lon - Longitude
   * @param {number} lat - Latitude
   * @param {Object} properties - Additional point properties (including emoji)
   */
  showMarker(lon, lat, properties = {}) {
    if (
      lon === undefined ||
      lat === undefined ||
      Number.isNaN(lon) ||
      Number.isNaN(lat)
    ) {
      console.warn("[TimelineMarker] Invalid coordinates:", lon, lat)
      return
    }

    const emoji = properties.emoji
    const hasEmoji = emoji && typeof emoji === "string" && emoji.trim() !== ""

    const data = {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [lon, lat],
          },
          properties: properties,
        },
      ],
    }

    this.update(data)
    this._currentEmoji = hasEmoji ? emoji : null

    // Update HTML emoji marker
    if (hasEmoji) {
      this._showEmojiMarker(lon, lat, emoji)
      this._hideCircleLayer()
    } else {
      this._removeEmojiMarker()
      this._showCircleLayer()
    }

    this.show()
  }

  /**
   * Get current emoji being displayed
   * @returns {string|null}
   */
  getCurrentEmoji() {
    return this._currentEmoji
  }

  /**
   * Hide the marker
   */
  hideMarker() {
    this._removeEmojiMarker()
    this.hide()
  }

  /**
   * Clear the marker data
   */
  clear() {
    this.update({
      type: "FeatureCollection",
      features: [],
    })
    this._currentEmoji = null
    this._removeEmojiMarker()
    this.hide()
  }

  /**
   * Show or update the HTML emoji marker
   * @private
   */
  _showEmojiMarker(lon, lat, emoji) {
    if (this._htmlMarker) {
      // Update position and emoji
      this._htmlMarker.setLngLat([lon, lat])
      this._htmlMarker.getElement().textContent = emoji
    } else {
      const el = document.createElement("div")
      el.className = "timeline-emoji-marker"
      el.textContent = emoji
      this._htmlMarker = new maplibregl.Marker({
        element: el,
        anchor: "center",
      })
        .setLngLat([lon, lat])
        .addTo(this.map)
    }
  }

  /**
   * Remove the HTML emoji marker
   * @private
   */
  _removeEmojiMarker() {
    if (this._htmlMarker) {
      this._htmlMarker.remove()
      this._htmlMarker = null
    }
  }

  /**
   * Hide the inner circle layer (when showing emoji)
   * @private
   */
  _hideCircleLayer() {
    try {
      if (this.map?.getLayer(this.id)) {
        this.map.setLayoutProperty(this.id, "visibility", "none")
      }
    } catch (_e) {
      // Layer might not exist yet
    }
  }

  /**
   * Show the inner circle layer (when no emoji)
   * @private
   */
  _showCircleLayer() {
    try {
      if (this.map?.getLayer(this.id)) {
        this.map.setLayoutProperty(this.id, "visibility", "visible")
      }
    } catch (_e) {
      // Layer might not exist yet
    }
  }
}
