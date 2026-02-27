import { BaseLayer } from "./base_layer"

/**
 * Recent point layer for displaying the most recent location in live mode
 * This layer is always visible when live mode is enabled, regardless of points layer visibility
 */
export class RecentPointLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "recent-point", visible: true, ...options })
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
