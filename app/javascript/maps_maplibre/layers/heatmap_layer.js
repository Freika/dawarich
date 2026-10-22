import { BaseLayer } from "./base_layer"

// Shared so the tiled points layer can draw an identical heatmap from its own source
export function heatmapPaint(opacity = 0.6) {
  return {
    // Tuned for typical Dawarich point density across country→street zoom;
    // first non-zero color stop kept above the sparse-noise floor.
    "heatmap-weight": 0.2,

    "heatmap-intensity": [
      "interpolate",
      ["linear"],
      ["zoom"],
      0,
      0.5,
      10,
      1,
      15,
      1.5,
      20,
      2,
      22,
      2,
    ],

    // Color ramp preserved from the retired Map v1 heatmap
    "heatmap-color": [
      "interpolate",
      ["linear"],
      ["heatmap-density"],
      0,
      "rgba(0,0,255,0)",
      0.4,
      "rgb(0,0,255)",
      0.6,
      "rgb(0,255,255)",
      0.7,
      "rgb(0,255,0)",
      0.8,
      "rgb(255,255,0)",
      1,
      "rgb(255,0,0)",
    ],

    // Radius in pixels, exponential growth
    "heatmap-radius": [
      "interpolate",
      ["exponential", 1.5],
      ["zoom"],
      10,
      8,
      13,
      15,
      15,
      25,
      20,
      50,
    ],

    // Visible when zoomed in, fades when zoomed out
    "heatmap-opacity": [
      "interpolate",
      ["linear"],
      ["zoom"],
      0,
      0.3,
      10,
      opacity,
      15,
      opacity,
    ],
  }
}

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
        paint: heatmapPaint(this.opacity),
      },
    ]
  }
}
