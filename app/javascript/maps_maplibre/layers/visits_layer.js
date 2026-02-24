import { BaseLayer } from "./base_layer"

/**
 * Visits layer showing suggested and confirmed visits
 * Yellow = suggested, Green = confirmed
 */
export class VisitsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "visits", ...options })
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
      // Visit circles
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 12,
          "circle-color": [
            "case",
            ["==", ["get", "status"], "confirmed"],
            "#22c55e", // Green for confirmed
            "#eab308", // Yellow for suggested
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.9,
        },
      },

      // Visit labels
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 11,
          "text-offset": [0, 1.5],
          "text-anchor": "top",
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      },
    ]
  }

  getLayerIds() {
    return [this.id, `${this.id}-labels`]
  }
}
