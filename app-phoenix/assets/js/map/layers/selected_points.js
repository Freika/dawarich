import { BaseLayer } from "./base.js"

export class SelectedPointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "selected-points", ...options })
    this.pointIds = []
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
        id: `${this.id}-highlight`,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 8,
          "circle-color": "#ef4444",
          "circle-opacity": 0.3,
        },
      },
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 5,
          "circle-color": "#ef4444",
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  getLayerIds() {
    return [`${this.id}-highlight`, this.id]
  }

  updateSelectedPoints(geojson) {
    this.data = geojson
    this.pointIds = geojson.features.map((f) => f.properties.id)
    this.update(geojson)
  }

  getSelectedPointIds() {
    return this.pointIds
  }

  clearSelection() {
    this.pointIds = []
    this.update({
      type: "FeatureCollection",
      features: [],
    })
  }

  getCount() {
    return this.pointIds.length
  }
}
