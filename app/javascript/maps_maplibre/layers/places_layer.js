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
          "circle-color": ["coalesce", ["get", "color"], "#6366f1"],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.85,
        },
      },
    ]
  }

  getLayerIds() {
    return [`${this.id}-radius-fill`, `${this.id}-radius-outline`, this.id]
  }

  add(data) {
    super.add(data)
    this.labels.sync(centerFeatures(data))
  }

  update(data) {
    super.update(data)
    this.labels.sync(centerFeatures(data))
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

function centerFeatures(data) {
  return (data?.features || []).filter(
    (feature) => feature.properties?.featureKind === "center",
  )
}
