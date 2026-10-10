import { BaseLayer } from "./base.js"
export function heatmapPaint(opacity = 0.6) {
  return {
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
