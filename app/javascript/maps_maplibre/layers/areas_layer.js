import { HtmlLabelManager } from "../utils/html_label_manager"
import { BaseLayer } from "./base_layer"

export class AreasLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "areas", ...options })
    this.labels = new HtmlLabelManager(map, {
      className: "map-html-label map-html-label--areas",
      anchor: "center",
      offset: [0, 0],
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
    ]
  }

  getLayerIds() {
    return [`${this.id}-fill`, `${this.id}-outline`]
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
