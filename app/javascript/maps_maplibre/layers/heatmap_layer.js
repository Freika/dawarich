import { BaseLayer } from "./base_layer"

/**
 * Heatmap layer showing point density
 * Uses MapLibre's native heatmap for performance
 */
export class HeatmapLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "heatmap", ...options })
    this.opacity = options.opacity || 0.6
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
        id: this.id,
        type: "heatmap",
        source: this.sourceId,
        paint: {
          // Fixed weight
          "heatmap-weight": 1,

          // low intensity to view major clusters
          "heatmap-intensity": [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            0.01,
            10,
            0.1,
            15,
            0.3,
          ],

          // Color ramp
          "heatmap-color": [
            "interpolate",
            ["linear"],
            ["heatmap-density"],
            0,
            "rgba(0,0,0,0)",
            0.4,
            "rgba(0,0,0,0)",
            0.65,
            "rgba(33,102,172,0.4)",
            0.7,
            "rgb(103,169,207)",
            0.8,
            "rgb(209,229,240)",
            0.9,
            "rgb(253,219,199)",
            0.95,
            "rgb(239,138,98)",
            1,
            "rgb(178,24,43)",
          ],

          // Radius in pixels, exponential growth
          "heatmap-radius": [
            "interpolate",
            ["exponential", 2],
            ["zoom"],
            10,
            5,
            15,
            10,
            20,
            160,
          ],

          // Visible when zoomed in, fades when zoomed out
          "heatmap-opacity": [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            0.3,
            10,
            this.opacity,
            15,
            this.opacity,
          ],
        },
      },
    ]
  }
}
