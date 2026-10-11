import { BaseLayer } from "./base.js"

export class AreasLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "areas", ...options })
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
      {
        id: `${this.id}-fill`,
        type: "fill",
        source: this.sourceId,
        paint: {
          "fill-color": "#ff0000",
          "fill-opacity": 0.4,
        },
      },
      {
        id: `${this.id}-outline`,
        type: "line",
        source: this.sourceId,
        paint: {
          "line-color": "#ff0000",
          "line-width": 3,
        },
      },
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 14,
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
    return [`${this.id}-fill`, `${this.id}-outline`, `${this.id}-labels`]
  }
}
