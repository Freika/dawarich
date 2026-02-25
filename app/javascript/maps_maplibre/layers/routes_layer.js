import { RouteSegmenter } from "../utils/route_segmenter"
import { BaseLayer } from "./base_layer"

/**
 * Routes layer showing travel paths
 * Connects points chronologically with solid color
 * Uses RouteSegmenter for route processing logic
 */
export class RoutesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "routes", ...options })
    this.maxGapHours = options.maxGapHours || 5 // Max hours between points to connect
    this.hoverSourceId = "routes-hover-source"
    this.baseSourceId = "routes-base-source"
    this.baseLayerId = "routes-base"
    this.baseData = null
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

  /**
   * Override add() to create main, base, and hover sources
   */
  add(data) {
    this.data = data
    const emptyGeoJSON = { type: "FeatureCollection", features: [] }

    // Add main source (speed-colored or regular routes, shown at zoom 8+)
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }

    // Add base source (original unsplit routes, shown below zoom 8)
    if (!this.map.getSource(this.baseSourceId)) {
      this.map.addSource(this.baseSourceId, {
        type: "geojson",
        data: this.baseData || data || emptyGeoJSON,
      })
    }

    // Add hover source (initially empty)
    if (!this.map.getSource(this.hoverSourceId)) {
      this.map.addSource(this.hoverSourceId, {
        type: "geojson",
        data: emptyGeoJSON,
      })
    }

    // Add layers
    const layers = this.getLayerConfigs()
    layers.forEach((layerConfig) => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig)
      }
    })

    this.setVisibility(this.visible)
  }

  getLayerConfigs() {
    return [
      // Base layer: original unsplit routes visible below zoom 8.
      // Speed-colored segments are tiny LineStrings that MapLibre's vector tile
      // system simplifies/drops at low zoom. This layer provides a fallback
      // so routes remain visible when zoomed out.
      {
        id: this.baseLayerId,
        type: "line",
        source: this.baseSourceId,
        maxzoom: 8,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#0000ff",
          "line-width": 3,
          "line-opacity": 0.8,
        },
      },
      // Main layer: speed-colored or regular routes, visible at zoom 8+
      {
        id: this.id,
        type: "line",
        source: this.sourceId,
        minzoom: 8,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          // Use color from feature properties if available, otherwise default blue
          "line-color": [
            "case",
            ["has", "color"],
            ["get", "color"],
            "#0000ff", // Default blue color (matching v1)
          ],
          "line-width": 3,
          "line-opacity": 0.8,
        },
      },
      {
        id: "routes-hover",
        type: "line",
        source: this.hoverSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#ffff00", // Yellow highlight
          "line-width": 8,
          "line-opacity": 1.0,
        },
      },
      // Note: routes-hit layer is added separately in LayerManager after points layer
      // for better interactivity (see _addRoutesHitLayer method)
    ]
  }

  /**
   * Override update() to also keep base source in sync.
   * When no explicit base data has been set (non-speed-colored mode),
   * the base source mirrors the main source for seamless zoom transitions.
   */
  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(data)
    }

    // Mirror main data to base source when no explicit base data exists
    if (!this.baseData) {
      const baseSource = this.map.getSource(this.baseSourceId)
      if (baseSource?.setData) {
        baseSource.setData(data)
      }
    }
  }

  /**
   * Set the base (original unsplit) routes data for low-zoom rendering.
   * Called when speed-colored routes are active so the base layer shows
   * the original full-length LineStrings below zoom 8.
   * @param {Object} data - GeoJSON FeatureCollection of original routes
   */
  updateBaseData(data) {
    this.baseData = data
    const baseSource = this.map.getSource(this.baseSourceId)
    if (baseSource?.setData) {
      baseSource.setData(data)
    }
  }

  /**
   * Override setVisibility to also control base and routes-hit layers
   * @param {boolean} visible - Show/hide layer
   */
  setVisibility(visible) {
    // Call parent to handle all layers from getLayerConfigs (base, main, hover)
    super.setVisibility(visible)

    // Also control routes-hit layer if it exists
    if (this.map.getLayer("routes-hit")) {
      const visibility = visible ? "visible" : "none"
      this.map.setLayoutProperty("routes-hit", "visibility", visibility)
    }
  }

  /**
   * Update hover layer with route geometry
   * @param {Object|null} feature - Route feature, FeatureCollection, or null to clear
   */
  setHoverRoute(feature) {
    const hoverSource = this.map.getSource(this.hoverSourceId)
    if (!hoverSource) return

    if (feature) {
      // Handle both single feature and FeatureCollection
      if (feature.type === "FeatureCollection") {
        hoverSource.setData(feature)
      } else {
        hoverSource.setData({
          type: "FeatureCollection",
          features: [feature],
        })
      }
    } else {
      hoverSource.setData({ type: "FeatureCollection", features: [] })
    }
  }

  /**
   * Override remove() to clean up base source, hover source, and hit layer
   */
  remove() {
    // Remove layers
    this.getLayerIds().forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    // Remove routes-hit layer if it exists
    if (this.map.getLayer("routes-hit")) {
      this.map.removeLayer("routes-hit")
    }

    // Remove sources
    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }
    if (this.map.getSource(this.baseSourceId)) {
      this.map.removeSource(this.baseSourceId)
    }
    if (this.map.getSource(this.hoverSourceId)) {
      this.map.removeSource(this.hoverSourceId)
    }

    this.data = null
    this.baseData = null
  }

  /**
   * Calculate haversine distance between two points in kilometers
   * Delegates to RouteSegmenter utility
   * @deprecated Use RouteSegmenter.haversineDistance directly
   * @param {number} lat1 - First point latitude
   * @param {number} lon1 - First point longitude
   * @param {number} lat2 - Second point latitude
   * @param {number} lon2 - Second point longitude
   * @returns {number} Distance in kilometers
   */
  static haversineDistance(lat1, lon1, lat2, lon2) {
    return RouteSegmenter.haversineDistance(lat1, lon1, lat2, lon2)
  }

  /**
   * Convert points to route LineStrings with splitting
   * Delegates to RouteSegmenter utility for processing
   * @param {Array} points - Points from API
   * @param {Object} options - Splitting options
   * @returns {Object} GeoJSON FeatureCollection
   */
  static pointsToRoutes(points, options = {}) {
    return RouteSegmenter.pointsToRoutes(points, options)
  }
}
