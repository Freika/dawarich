import { BaseLayer } from "./base_layer"

/**
 * Layer for displaying selected points with distinct styling
 */
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
      // Outer circle (highlight)
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
      // Inner circle (selected point)
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

  /**
   * Get layer IDs for this layer
   */
  getLayerIds() {
    return [`${this.id}-highlight`, this.id]
  }

  /**
   * Update selected points and store their IDs
   */
  updateSelectedPoints(geojson) {
    this.data = geojson

    // Extract point IDs
    this.pointIds = geojson.features.map((f) => f.properties.id)

    // Update map source
    this.update(geojson)

    console.log(
      "[SelectedPointsLayer] Updated with",
      this.pointIds.length,
      "points",
    )
  }

  /**
   * Get IDs of selected points
   */
  getSelectedPointIds() {
    return this.pointIds
  }

  /**
   * Clear selected points
   */
  clearSelection() {
    this.pointIds = []
    this.update({
      type: "FeatureCollection",
      features: [],
    })
  }

  /**
   * Get count of selected points
   */
  getCount() {
    return this.pointIds.length
  }
}
