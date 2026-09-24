import { BaseLayer } from "./base_layer"

const BASE_TRACKS_LAYER_ID = "tracks-mvt"
const FLOW_PIXELS_PER_SECOND = 40
const FLOW_MAX_PAINTS_PER_SECOND = 30
const FLOW_MIN_CYCLE_MS = 750
const FLOW_FALLBACK_CYCLE_MS = 3000
const EARTH_CIRCUMFERENCE_METERS = 40075016.686
const TILE_SIZE_PIXELS = 512

/**
 * Focused Track selection and segment visualization overlay.
 * Canonical journey lines are rendered exclusively by TracksMvtLayer.
 */
export class TracksLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "tracks", ...options })
    this.segmentSourceId = "tracks-segments-source"
    this.segmentLayerId = "tracks-segments"
    this.selectionSourceId = "tracks-selection-source"

    // Selection layer IDs (3-layer stack: main + border + flow gradient)
    this.selectionBorderLayerId = "tracks-selection-border"
    this.flowLayerId = "tracks-selection-flow"

    // Flow animation state
    this.animationFrame = null
    this.animationActive = false
    this.segmentsActive = false
    this.selectedTrackLength = 0 // meters
    this.selectedFeature = null
    this.selectionRevision = 0
    this.flowTrackColor = "#ff0000"

    this.onSegmentHover = null // Callback for segment hover events
    this.onSegmentLeave = null // Callback for segment leave events
  }

  getLayerConfigs() {
    return [
      // Selection Layer 1: White border (widest, bottom of selection stack)
      {
        id: this.selectionBorderLayerId,
        type: "line",
        source: this.selectionSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#ffffff",
          "line-width": 10,
          "line-opacity": 0.9,
        },
      },
      // Selection Layer 2: Flowing gradient dashes (line-gradient animation)
      {
        id: this.flowLayerId,
        type: "line",
        source: this.selectionSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-width": 6,
          "line-gradient": this._buildFlowGradient(0),
        },
      },
    ]
  }

  /** Add only the exact, focused selection source. */
  add(data) {
    this.data = data

    // lineMetrics is required for the animated line-gradient.
    if (!this.map.getSource(this.selectionSourceId)) {
      this.map.addSource(this.selectionSourceId, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        lineMetrics: true,
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

  /**
   * Set selected track for highlighting
   * @param {Object|null} feature - Track feature or null to clear
   */
  setSelectedTrack(feature, { preserveSegments = false } = {}) {
    if (!this.map) return

    const selectionSource = this.map.getSource(this.selectionSourceId)
    if (!selectionSource) return

    this.selectedFeature = feature || null
    this.selectionRevision += 1

    if (feature) {
      this.flowTrackColor = feature.properties?.color || "#ff0000"
      if (!preserveSegments) this.hideSegments()
      const geometry = feature.geometry
      const lines =
        geometry?.type === "MultiLineString"
          ? geometry.coordinates
          : [geometry?.coordinates || []]
      this.selectedTrackLength = lines.reduce(
        (length, coordinates) => length + this._computeLineLength(coordinates),
        0,
      )
      selectionSource.setData({
        type: "FeatureCollection",
        features: [feature],
      })
      this._raiseSelectionAboveBaseTracks()
      this._startFlowAnimation()
    } else {
      this._stopFlowAnimation()
      if (!preserveSegments) this.hideSegments()
      this.selectedTrackLength = 0
      selectionSource.setData({ type: "FeatureCollection", features: [] })
    }
  }

  _raiseSelectionAboveBaseTracks() {
    const ids = this.map.getStyle?.()?.layers?.map((layer) => layer.id) ?? []
    const baseIndex = ids.indexOf(BASE_TRACKS_LAYER_ID)
    if (baseIndex === -1) return

    const layerAboveBase = ids[baseIndex + 1]
    for (const id of [this.selectionBorderLayerId, this.flowLayerId]) {
      const index = ids.indexOf(id)
      if (index !== -1 && index < baseIndex)
        this.map.moveLayer(id, layerAboveBase)
    }
  }

  /**
   * Build a line-gradient expression with flowing dash pattern.
   *
   * Creates an interpolated gradient along line-progress (0→1) that alternates
   * between the track color and semi-transparent white highlight dashes.
   * Shifting `phase` (0→1) each frame produces smooth continuous motion.
   *
   * @param {number} phase - Animation phase from 0 to 1
   * @returns {Array} MapLibre line-gradient expression
   */
  _buildFlowGradient(
    phase,
    { baseColor, highlightColor, numDashes: numDashesOpt } = {},
  ) {
    const numDashes = numDashesOpt || 6
    const dashFraction = 0.15 // 15% of one period is the dash
    const softEdge = 0.04 // fade width at dash boundaries
    const highlight = highlightColor || "rgba(255,255,255,0.5)"
    const trackColor = baseColor || this.flowTrackColor
    const period = 1 / numDashes

    const stops = []

    // Add stops for each dash (including overflow at boundaries)
    for (let i = -1; i <= numDashes; i++) {
      const center = (i + phase) * period
      const halfDash = (dashFraction * period) / 2

      const fadeInStart = center - halfDash - softEdge
      const dashStart = center - halfDash
      const dashEnd = center + halfDash
      const fadeOutEnd = center + halfDash + softEdge

      // Only add stops that fall within or near [0, 1]
      if (fadeOutEnd < 0 || fadeInStart > 1) continue

      if (fadeInStart >= 0 && fadeInStart <= 1) {
        stops.push([fadeInStart, trackColor])
      }
      if (dashStart >= 0 && dashStart <= 1) {
        stops.push([dashStart, highlight])
      }
      if (dashEnd >= 0 && dashEnd <= 1) {
        stops.push([dashEnd, highlight])
      }
      if (fadeOutEnd >= 0 && fadeOutEnd <= 1) {
        stops.push([fadeOutEnd, trackColor])
      }
    }

    // Sort by position
    stops.sort((a, b) => a[0] - b[0])

    // Ensure endpoints exist
    if (stops.length === 0 || stops[0][0] > 0) {
      stops.unshift([0, trackColor])
    }
    if (stops[stops.length - 1][0] < 1) {
      stops.push([1, trackColor])
    }

    // Deduplicate stops at same position (keep last)
    const deduped = []
    for (let i = 0; i < stops.length; i++) {
      if (
        i < stops.length - 1 &&
        Math.abs(stops[i][0] - stops[i + 1][0]) < 1e-6
      ) {
        continue
      }
      deduped.push(stops[i])
    }

    // Build the expression: ["interpolate", ["linear"], ["line-progress"], pos, color, ...]
    const expr = ["interpolate", ["linear"], ["line-progress"]]
    for (const [pos, color] of deduped) {
      expr.push(pos, color)
    }

    return expr
  }

  /**
   * Start the flowing gradient animation for the selected track.
   * The dashes travel at a constant on-screen speed whatever the zoom, and
   * the gradient is rebuilt at most FLOW_MAX_PAINTS_PER_SECOND times.
   */
  _startFlowAnimation() {
    if (this.animationActive) return
    this.animationActive = true

    let phase = 0
    let lastTimestamp = null
    let lastPaintAt = Number.NEGATIVE_INFINITY

    const animate = (timestamp) => {
      if (!this.animationActive) return
      if (!this.map || typeof this.map.getLayer !== "function") {
        this._stopFlowAnimation()
        return
      }

      const numDashes = this._flowDashCount()
      if (lastTimestamp !== null) {
        phase =
          (phase + (timestamp - lastTimestamp) / this._flowCycleMs(numDashes)) %
          1
      }
      lastTimestamp = timestamp

      if (timestamp - lastPaintAt >= 1000 / FLOW_MAX_PAINTS_PER_SECOND - 1) {
        lastPaintAt = timestamp
        try {
          if (this.map.getLayer(this.flowLayerId)) {
            // Transparent base when segments visible so their colors show through
            const baseColor = this.segmentsActive
              ? "rgba(255,255,255,0)"
              : undefined

            this.map.setPaintProperty(
              this.flowLayerId,
              "line-gradient",
              this._buildFlowGradient(phase, { baseColor, numDashes }),
            )
          }
        } catch (e) {
          console.warn("[TracksLayer] Animation frame error:", e)
        }
      }

      if (this.animationActive) {
        this.animationFrame = requestAnimationFrame(animate)
      }
    }

    this.animationFrame = requestAnimationFrame(animate)
  }

  // ~400m per dash; clamp to [4, 30] for visual consistency
  _flowDashCount() {
    if (!(this.selectedTrackLength > 0)) return 6

    return Math.max(4, Math.min(30, Math.round(this.selectedTrackLength / 400)))
  }

  _flowCycleMs(numDashes) {
    const zoom = this.map.getZoom?.()
    const latitude = this.map.getCenter?.()?.lat
    if (
      !(this.selectedTrackLength > 0) ||
      !Number.isFinite(zoom) ||
      !Number.isFinite(latitude)
    ) {
      return FLOW_FALLBACK_CYCLE_MS
    }

    const metersPerPixel =
      (EARTH_CIRCUMFERENCE_METERS * Math.cos((latitude * Math.PI) / 180)) /
      (TILE_SIZE_PIXELS * 2 ** zoom)
    const periodPixels = this.selectedTrackLength / numDashes / metersPerPixel

    return Math.max(
      FLOW_MIN_CYCLE_MS,
      (periodPixels / FLOW_PIXELS_PER_SECOND) * 1000,
    )
  }

  /**
   * Stop the flowing gradient animation
   */
  _stopFlowAnimation() {
    this.animationActive = false
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame)
      this.animationFrame = null
    }
  }

  /**
   * Compute the total length of a LineString in meters (haversine).
   * @param {Array} coordinates - Array of [lon, lat] pairs
   * @returns {number} Length in meters
   */
  _computeLineLength(coordinates) {
    const toRad = (deg) => (deg * Math.PI) / 180
    let total = 0
    for (let i = 1; i < coordinates.length; i++) {
      const [lon1, lat1] = coordinates[i - 1]
      const [lon2, lat2] = coordinates[i]
      const dLat = toRad(lat2 - lat1)
      const dLon = toRad(lon2 - lon1)
      const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
      total += 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }
    return total
  }

  /**
   * Show segment highlighting for a track (debug mode)
   * @param {Object} trackFeature - The track GeoJSON feature
   * @param {Array} segments - Array of segment data with mode, color, start_index, end_index
   */
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

    // Move the flow layer on top of segments so dashes overlay the
    // transport-mode colors. The animation loop switches to a transparent
    // base when segmentsActive is true, letting segment colors show through.
    this.segmentsActive = true
    if (this.map.getLayer(this.flowLayerId)) {
      this.map.moveLayer(this.flowLayerId)
    }
  }

  /**
   * Hide segment highlighting
   */
  hideSegments() {
    this.segmentsActive = false

    // Hide segment layer
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "none")
    }
  }

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
  }

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
   * Override remove to also clean up segment and selection layers
   */
  remove() {
    // Stop animation first
    this._stopFlowAnimation()

    // Remove segment event handlers
    this._removeSegmentHoverEvents()

    if (!this.map) return

    // Remove segment layer and source
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.removeLayer(this.segmentLayerId)
    }
    if (this.map.getSource(this.segmentSourceId)) {
      this.map.removeSource(this.segmentSourceId)
    }
    // Remove selection layers (border + flow)
    ;[this.flowLayerId, this.selectionBorderLayerId].forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    // Remove selection source
    if (this.map.getSource(this.selectionSourceId)) {
      this.map.removeSource(this.selectionSourceId)
    }

    // Call parent remove
    super.remove()
  }
}
