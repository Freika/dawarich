import { HtmlLabelManager } from "../utils/html_label_manager"
import { BaseLayer } from "./base_layer"

export class PlacesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "places", ...options })
    this.labels = new HtmlLabelManager(map, {
      className: "map-html-label map-html-label--places",
      anchor: "top",
      offset: [0, 14],
      visible: this.visible,
    })
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
    ]
  }

  getLayerIds() {
    return [this.id]
  }

  add(data) {
    super.add(data)
    this.labels.sync(data?.features || [])
  }

  update(data) {
    super.update(data)
    this.labels.sync(data?.features || [])
  }

  remove() {
    this.labels.clear()
    super.remove()
  }

  setVisibility(visible) {
    super.setVisibility(visible)
    this.labels?.setVisibility(visible)
  }
}
