import { BaseLayer } from "./base_layer"

/**
 * Places layer showing user-created places with tags
 * Different colors based on tags
 */
export class PlacesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "places", ...options })
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
      // Visit Radius boundaries. These remain deliberately subtle so the
      // Places layer can stay useful without obscuring routes and points.
      {
        id: `${this.id}-radius-fill`,
        type: "fill",
        source: this.sourceId,
        filter: ["==", ["get", "featureKind"], "boundary"],
        paint: {
          "fill-color": ["coalesce", ["get", "color"], "#6366f1"],
          "fill-opacity": 0.1,
        },
      },
      {
        id: `${this.id}-radius-outline`,
        type: "line",
        source: this.sourceId,
        filter: ["==", ["get", "featureKind"], "boundary"],
        paint: {
          "line-color": ["coalesce", ["get", "color"], "#6366f1"],
          "line-width": 2,
          "line-opacity": 0.65,
        },
      },

      // Place centers
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        filter: ["==", ["get", "featureKind"], "center"],
        paint: {
          "circle-radius": 10,
          "circle-color": [
            "coalesce",
            ["get", "color"], //  Use tag color if available
            "#6366f1", // Default indigo color
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.85,
        },
      },

      // Place labels
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
        filter: ["==", ["get", "featureKind"], "center"],
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 11,
          "text-offset": [0, 1.3],
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
    return [
      `${this.id}-radius-fill`,
      `${this.id}-radius-outline`,
      this.id,
      `${this.id}-labels`,
    ]
  }
}
