import { greatCircleLines } from "../../utils/flight_arcs"

/**
 * A selected track's coloured segments and their hover events.
 * Mixed into the controller; `this` is the controller.
 */
export const trackSegments = {
  showSegments(trackFeature, segments) {
    if (trackFeature?.geometry?.type !== "LineString") {
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
        // Prefer server-provided segment geometry (time-anchored segments);
        // fall back to index slicing for legacy index-anchored segments.
        let segmentCoords
        if (segment.coordinates && segment.coordinates.length >= 2) {
          segmentCoords = segment.coordinates
        } else {
          const startIdx = Math.max(0, segment.start_index || 0)
          const endIdx = Math.min(
            coords.length - 1,
            (segment.end_index || startIdx) + 1,
          )
          segmentCoords = coords.slice(startIdx, endIdx + 1)
        }

        const lines = greatCircleLines(segmentCoords).filter(
          (line) => line.length >= 2,
        )
        if (lines.length === 0) {
          return null
        }

        return {
          type: "Feature",
          geometry:
            lines.length === 1
              ? { type: "LineString", coordinates: lines[0] }
              : { type: "MultiLineString", coordinates: lines },
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

    // Move the flow layer on top of segments so dashes overlay the
    // transport-mode colors. The animation loop switches to a transparent
    // base when segmentsActive is true, letting segment colors show through.
    this.segmentsActive = true
    if (this.map.getLayer(this.flowLayerId)) {
      this.map.moveLayer(this.flowLayerId)
    }
  },

  /**
   * Hide segment highlighting
   */
  hideSegments() {
    this.segmentsActive = false

    // Hide segment layer
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "none")
    }
  },

  /**
   * Set up hover event handlers for segment layer
   */
  _setupSegmentHoverEvents() {
    // Store bound handlers for later cleanup
    this._segmentMouseEnterHandler = (e) => {
      this.map.getCanvas().style.cursor = "pointer"

      if (e.features?.[0] && this.onSegmentHover) {
        const segmentIndex = e.features[0].properties.segmentIndex
        this.onSegmentHover(segmentIndex)
      }
    }

    this._segmentMouseLeaveHandler = () => {
      this.map.getCanvas().style.cursor = ""

      if (this.onSegmentLeave) {
        this.onSegmentLeave()
      }
    }

    this.map.on(
      "mouseenter",
      this.segmentLayerId,
      this._segmentMouseEnterHandler,
    )
    this.map.on(
      "mouseleave",
      this.segmentLayerId,
      this._segmentMouseLeaveHandler,
    )
  },

  /**
   * Remove segment hover event handlers
   */
  _removeSegmentHoverEvents() {
    if (this._segmentMouseEnterHandler) {
      this.map.off(
        "mouseenter",
        this.segmentLayerId,
        this._segmentMouseEnterHandler,
      )
      this._segmentMouseEnterHandler = null
    }
    if (this._segmentMouseLeaveHandler) {
      this.map.off(
        "mouseleave",
        this.segmentLayerId,
        this._segmentMouseLeaveHandler,
      )
      this._segmentMouseLeaveHandler = null
    }
  },

  /**
   * Set callback for segment hover events
   * @param {Function} callback - Called with segmentIndex when hovering a segment
   */
  setSegmentHoverCallback(callback) {
    this.onSegmentHover = callback
  },

  /**
   * Set callback for segment leave events
   * @param {Function} callback - Called when mouse leaves a segment
   */
  setSegmentLeaveCallback(callback) {
    this.onSegmentLeave = callback
  },
}
