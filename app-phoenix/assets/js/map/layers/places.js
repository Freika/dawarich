import { BaseLayer } from "./base.js"
import { createPlaceLabels } from "./place_labels.js"

export class PlacesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "places", ...options })
    this.library = options.library
  }

  add(data, beforeId = null) {
    if (!this.labels && this.library?.Marker)
      this.labels = createPlaceLabels({ map: this.map, library: this.library, layerId: this.id })
    super.add(data, beforeId)
    this.labels?.refresh()
  }

  setVisibility(visible) {
    super.setVisibility(visible)
    this.labels?.visibility(visible)
  }

  remove() {
    this.labels?.destroy()
    this.labels = null
    super.remove()
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
    const layers = [
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 10,
          "circle-color": ["coalesce", ["get", "color"], "#6366f1"],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.85,
        },
      },
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
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
    return this.library?.Marker ? layers.slice(0, 1) : layers
  }

  getLayerIds() {
    return [this.id, `${this.id}-labels`]
  }
}
