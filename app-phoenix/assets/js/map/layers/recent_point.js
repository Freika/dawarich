import { BaseLayer } from "./base.js"

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

  clear() {
    this.update({
      type: "FeatureCollection",
      features: [],
    })
  }
}
