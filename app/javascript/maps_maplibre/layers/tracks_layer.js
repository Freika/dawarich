import { BaseLayer } from "./base_layer"

/**
 * Tracks layer for saved routes with segment visualization support
 *
 * Debug feature: When a track is clicked, segments are highlighted
 * with different colors based on transportation mode.
 */
export class TracksLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "tracks", ...options })
    this.segmentSourceId = "tracks-segments-source"
    this.segmentLayerId = "tracks-segments"
    this.onSegmentHover = null // Callback for segment hover events
    this.onSegmentLeave = null // Callback for segment leave events
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
        type: "line",
        source: this.sourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": ["get", "color"],
          "line-width": 4,
          "line-opacity": 0.7,
        },
      },
    ]
  }

  /**
   * Show segment highlighting for a track (debug mode)
   * @param {Object} trackFeature - The track GeoJSON feature
   * @param {Array} segments - Array of segment data with mode, color, start_index, end_index
   */
  showSegments(trackFeature, segments) {
    if (
      !trackFeature ||
      !trackFeature.geometry ||
      trackFeature.geometry.type !== "LineString"
    ) {
      return
    }

    if (!segments || segments.length === 0) {
      this.hideSegments()
      return
    }

    const coords = trackFeature.geometry.coordinates
    if (coords.length < 2) {
      return
    }

    // Create line features for each segment
    const segmentFeatures = segments
      .map((segment, idx) => {
        const startIdx = Math.max(0, segment.start_index || 0)
        const endIdx = Math.min(
          coords.length - 1,
          (segment.end_index || startIdx) + 1,
        )

        // Extract coordinates for this segment
        const segmentCoords = coords.slice(startIdx, endIdx + 1)

        // Need at least 2 points for a line
        if (segmentCoords.length < 2) {
          return null
        }

        return {
          type: "Feature",
          geometry: {
            type: "LineString",
            coordinates: segmentCoords,
          },
          properties: {
            mode: segment.mode,
            color: segment.color || "#9E9E9E",
            emoji: segment.emoji || "❓",
            segmentIndex: idx,
          },
        }
      })
      .filter(Boolean)

    const segmentGeoJSON = {
      type: "FeatureCollection",
      features: segmentFeatures,
    }

    // Add or update segment source and layer
    if (!this.map.getSource(this.segmentSourceId)) {
      this.map.addSource(this.segmentSourceId, {
        type: "geojson",
        data: segmentGeoJSON,
      })

      this.map.addLayer({
        id: this.segmentLayerId,
        type: "line",
        source: this.segmentSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": ["get", "color"],
          "line-width": 6,
          "line-opacity": 0.9,
        },
      })

      // Set up hover events for segments
      this._setupSegmentHoverEvents()
    } else {
      this.map.getSource(this.segmentSourceId).setData(segmentGeoJSON)
      // Make sure layer is visible
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "visible")
    }

    // Dim the original track to highlight segments
    if (this.map.getLayer(this.id)) {
      this.map.setPaintProperty(this.id, "line-opacity", 0.3)
    }
  }

  /**
   * Hide segment highlighting
   */
  hideSegments() {
    // Hide segment layer if it exists
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "none")
    }

    // Restore original track opacity
    if (this.map.getLayer(this.id)) {
      this.map.setPaintProperty(this.id, "line-opacity", 0.7)
    }
  }

  /**
   * Set up hover event handlers for segment layer
   */
  _setupSegmentHoverEvents() {
    // Mouse enter on segment
    this.map.on("mouseenter", this.segmentLayerId, (e) => {
      this.map.getCanvas().style.cursor = "pointer"

      if (e.features?.[0] && this.onSegmentHover) {
        const segmentIndex = e.features[0].properties.segmentIndex
        this.onSegmentHover(segmentIndex)
      }
    })

    // Mouse leave segment
    this.map.on("mouseleave", this.segmentLayerId, () => {
      this.map.getCanvas().style.cursor = ""

      if (this.onSegmentLeave) {
        this.onSegmentLeave()
      }
    })
  }

  /**
   * Set callback for segment hover events
   * @param {Function} callback - Called with segmentIndex when hovering a segment
   */
  setSegmentHoverCallback(callback) {
    this.onSegmentHover = callback
  }

  /**
   * Set callback for segment leave events
   * @param {Function} callback - Called when mouse leaves a segment
   */
  setSegmentLeaveCallback(callback) {
    this.onSegmentLeave = callback
  }

  /**
   * Update a single track feature in the layer
   * Used when a track is recalculated after point movement
   * @param {Object} trackFeature - The updated GeoJSON feature
   * @param {Object} options - Options for the update
   * @param {boolean} options.preserveSelection - If true and this track is selected, re-apply selection
   * @returns {Object|false} - The updated feature if successful, false otherwise
   */
  updateTrackFeature(trackFeature, options = {}) {
    if (!trackFeature || !trackFeature.properties?.id) {
      console.warn("[TracksLayer] Cannot update track: invalid feature")
      return false
    }

    const source = this.map.getSource(this.sourceId)
    if (!source) {
      console.warn("[TracksLayer] Cannot update track: source not found")
      return false
    }

    // Get current data
    const currentData = this.data || source._data
    if (!currentData || !currentData.features) {
      console.warn("[TracksLayer] Cannot update track: no data")
      return false
    }

    // Find and update the track
    const trackId = trackFeature.properties.id
    const featureIndex = currentData.features.findIndex(
      (f) => f.properties?.id === trackId,
    )

    if (featureIndex === -1) {
      console.warn(`[TracksLayer] Track ${trackId} not found in layer`)
      return false
    }

    // Update the feature in place
    currentData.features[featureIndex] = trackFeature

    // Update the source
    source.setData(currentData)

    // Also update our cached data reference
    this.data = currentData

    // If this track has segments displayed, update them too
    if (options.preserveSelection && this.map.getSource(this.segmentSourceId)) {
      const segments = trackFeature.properties?.segments || []
      const parsedSegments =
        typeof segments === "string" ? JSON.parse(segments) : segments

      if (parsedSegments.length > 0) {
        this.showSegments(trackFeature, parsedSegments)
      }
    }

    console.log(`[TracksLayer] Updated track ${trackId}`)
    return trackFeature
  }

  /**
   * Override remove to also clean up segment layer
   */
  remove() {
    // Remove segment layer and source
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.removeLayer(this.segmentLayerId)
    }
    if (this.map.getSource(this.segmentSourceId)) {
      this.map.removeSource(this.segmentSourceId)
    }

    // Call parent remove
    super.remove()
  }
}
