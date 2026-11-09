import { getMarkerStrokeColor } from "../utils/marker_theme"
import { heatmapPaint } from "./heatmap_layer"
import { VectorTileLayer } from "./vector_tile_layer"

export class PointsMvtLayer extends VectorTileLayer {
  // Ten minutes in a cell contributes a heatmap weight of one.
  static HEATMAP_DWELL_REFERENCE_SECONDS = 600

  constructor(map, options = {}) {
    super(map, { id: "points-mvt", ...options })
    this.tileKind = "points"
    this.flightBounds = ["timestamp", "max_timestamp"]
    this.styleName = options.styleName
    // Heatmap rides the same source and same lifecycle, toggled independently
    this.heatmapVisible = options.heatmapVisible === true
    this._visibleCirclePaint = {
      "circle-opacity": 1,
      "circle-stroke-opacity": 1,
    }
  }

  add(data, beforeId = null) {
    super.add(data, beforeId)
    for (const [property, value] of Object.entries(this._visibleCirclePaint)) {
      this.setCircleOpacity(property, value)
    }
  }

  static HEATMAP_LAYER_ID = "points-mvt-heatmap"

  static CIRCLE_RADIUS = 6

  static CIRCLE_STROKE_WIDTH = 2

  setHeatmapVisible(visible) {
    this.heatmapVisible = visible
    this._applyLayerVisibility(PointsMvtLayer.HEATMAP_LAYER_ID, visible)
  }

  // Sub-layers are toggled independently, so they cannot share BaseLayer's flag
  setVisibility(visible) {
    this.visible = visible
    this._applyLayerVisibility(this.id, visible)
    this._applyLayerVisibility(
      PointsMvtLayer.HEATMAP_LAYER_ID,
      this.heatmapVisible,
    )
  }

  setCircleOpacity(property, value) {
    this._visibleCirclePaint[property] = value
    if (this.map.getLayer(this.id)) {
      this.map.setPaintProperty?.(this.id, property, value)
    }
  }

  _applyLayerVisibility(layerId, visible) {
    if (!this.map.getLayer(layerId)) return

    this.map.setLayoutProperty(
      layerId,
      "visibility",
      visible ? "visible" : "none",
    )
  }

  getLayerConfigs() {
    return [
      {
        id: PointsMvtLayer.HEATMAP_LAYER_ID,
        type: "heatmap",
        source: this.sourceId,
        "source-layer": "points",
        paint: {
          ...heatmapPaint(),
          // Linear dwell weights preserve time across sampling rates and cells.
          // Keep the count-based fallback for cached tiles without dwell.
          "heatmap-weight": [
            "case",
            ["has", "dwell"],
            [
              "/",
              ["get", "dwell"],
              PointsMvtLayer.HEATMAP_DWELL_REFERENCE_SECONDS,
            ],
            [
              "min",
              1,
              [
                "+",
                0.2,
                ["*", 0.094, ["ln", ["coalesce", ["get", "count"], 1]]],
              ],
            ],
          ],
        },
      },
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        "source-layer": "points",
        paint: {
          "circle-color": "#3b82f6",
          "circle-radius": PointsMvtLayer.CIRCLE_RADIUS,
          "circle-stroke-width": PointsMvtLayer.CIRCLE_STROKE_WIDTH,
          "circle-stroke-color": getMarkerStrokeColor(this.styleName),
        },
      },
    ]
  }
}
