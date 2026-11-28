import { BaseLayer } from "./base_layer"

export class EditableTrackLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "editable-track-line", ...options })
    this.segmentsLayerId = "editable-track-segments"
    this.pointsLayerId = "track-points"
    this.successLayerId = "edit-success-indicator"
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "line",
        source: this.sourceId,
        filter: [
          "any",
          [
            "all",
            ["==", ["get", "kind"], "track"],
            ["!=", ["get", "has_segments"], true],
          ],
          ["==", ["get", "kind"], "uncovered-track"],
        ],
        layout: { "line-join": "round", "line-cap": "round" },
        paint: { "line-color": "#6366F1", "line-width": 5 },
      },
      {
        id: this.segmentsLayerId,
        type: "line",
        source: this.sourceId,
        filter: ["==", ["get", "kind"], "segment"],
        layout: { "line-join": "round", "line-cap": "round" },
        paint: {
          "line-color": ["coalesce", ["get", "color"], "#6366F1"],
          "line-width": 5,
        },
      },
      {
        id: this.pointsLayerId,
        type: "circle",
        source: this.sourceId,
        filter: ["==", ["get", "kind"], "point"],
        paint: {
          "circle-color": "#10b981",
          "circle-radius": 7,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
      {
        id: this.successLayerId,
        type: "circle",
        source: this.sourceId,
        filter: ["==", ["get", "id"], -1],
        paint: {
          "circle-color": "transparent",
          "circle-radius": 10,
          "circle-stroke-width": 3,
          "circle-stroke-color": "#22c55e",
          "circle-stroke-opacity": 0,
        },
      },
    ]
  }

  setData(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source) source.setData(data)
  }
}
