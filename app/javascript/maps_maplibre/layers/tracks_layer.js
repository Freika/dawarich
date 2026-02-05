import { BaseLayer } from "./base_layer";

/**
 * Tracks layer for saved routes with segment visualization support
 *
 * Debug feature: When a track is clicked, segments are highlighted
 * with different colors based on transportation mode.
 */
export class TracksLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "tracks", ...options });
    this.segmentSourceId = "tracks-segments-source";
    this.segmentLayerId = "tracks-segments";
    this.selectionSourceId = "tracks-selection-source";

    // Selection layer IDs (3-layer stack: main + border + flow gradient)
    this.selectionBorderLayerId = "tracks-selection-border";
    this.flowLayerId = "tracks-selection-flow";

    // Flow animation state
    this.animationFrame = null;
    this.animationActive = false;
    this.segmentsActive = false;
    this.selectedTrackLength = 0; // meters
    this.flowTrackColor = "#ff0000";

    this.onSegmentHover = null; // Callback for segment hover events
    this.onSegmentLeave = null; // Callback for segment leave events
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    };
  }

  getLayerConfigs() {
    return [
      // Main tracks layer (bottom)
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
    ];
  }

  /**
   * Override add() to create both main and selection sources
   */
  add(data) {
    this.data = data;

    // Add main source
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig());
    }

    // Add selection source (initially empty, lineMetrics required for line-gradient)
    if (!this.map.getSource(this.selectionSourceId)) {
      this.map.addSource(this.selectionSourceId, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        lineMetrics: true,
      });
    }

    // Add layers
    const layers = this.getLayerConfigs();
    layers.forEach((layerConfig) => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig);
      }
    });

    this.setVisibility(this.visible);
  }

  /**
   * Set selected track for highlighting
   * @param {Object|null} feature - Track feature or null to clear
   */
  setSelectedTrack(feature) {
    const selectionSource = this.map.getSource(this.selectionSourceId);
    if (!selectionSource) return;

    if (feature) {
      this.flowTrackColor = feature.properties?.color || "#ff0000";
      this.segmentsActive = false;
      this.selectedTrackLength = this._computeLineLength(
        feature.geometry?.coordinates || [],
      );
      selectionSource.setData({
        type: "FeatureCollection",
        features: [feature],
      });
      this._startFlowAnimation();
    } else {
      this._stopFlowAnimation();
      this.segmentsActive = false;
      this.selectedTrackLength = 0;
      selectionSource.setData({ type: "FeatureCollection", features: [] });
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
  _buildFlowGradient(phase, { baseColor, highlightColor, numDashes: numDashesOpt } = {}) {
    const numDashes = numDashesOpt || 6;
    const dashFraction = 0.15; // 15% of one period is the dash
    const softEdge = 0.04; // fade width at dash boundaries
    const highlight = highlightColor || "rgba(255,255,255,0.5)";
    const trackColor = baseColor || this.flowTrackColor;
    const period = 1 / numDashes;

    const stops = [];

    // Add stops for each dash (including overflow at boundaries)
    for (let i = -1; i <= numDashes; i++) {
      const center = (i + phase) * period;
      const halfDash = (dashFraction * period) / 2;

      const fadeInStart = center - halfDash - softEdge;
      const dashStart = center - halfDash;
      const dashEnd = center + halfDash;
      const fadeOutEnd = center + halfDash + softEdge;

      // Only add stops that fall within or near [0, 1]
      if (fadeOutEnd < 0 || fadeInStart > 1) continue;

      if (fadeInStart >= 0 && fadeInStart <= 1) {
        stops.push([fadeInStart, trackColor]);
      }
      if (dashStart >= 0 && dashStart <= 1) {
        stops.push([dashStart, highlight]);
      }
      if (dashEnd >= 0 && dashEnd <= 1) {
        stops.push([dashEnd, highlight]);
      }
      if (fadeOutEnd >= 0 && fadeOutEnd <= 1) {
        stops.push([fadeOutEnd, trackColor]);
      }
    }

    // Sort by position
    stops.sort((a, b) => a[0] - b[0]);

    // Ensure endpoints exist
    if (stops.length === 0 || stops[0][0] > 0) {
      stops.unshift([0, trackColor]);
    }
    if (stops[stops.length - 1][0] < 1) {
      stops.push([1, trackColor]);
    }

    // Deduplicate stops at same position (keep last)
    const deduped = [];
    for (let i = 0; i < stops.length; i++) {
      if (i < stops.length - 1 && Math.abs(stops[i][0] - stops[i + 1][0]) < 1e-6) {
        continue;
      }
      deduped.push(stops[i]);
    }

    // Build the expression: ["interpolate", ["linear"], ["line-progress"], pos, color, ...]
    const expr = ["interpolate", ["linear"], ["line-progress"]];
    for (const [pos, color] of deduped) {
      expr.push(pos, color);
    }

    return expr;
  }

  /**
   * Start the flowing gradient animation for the selected track.
   * Uses setPaintProperty to update the line-gradient expression each frame,
   * which triggers MapLibre's internal gradientVersion increment and
   * texture regeneration without the overhead of removeLayer/addLayer.
   * Cycle duration: 3000ms (one full period shift per 3 seconds).
   */
  _startFlowAnimation() {
    if (this.animationActive) return;
    this.animationActive = true;

    const cycleDuration = 3000;
    let startTime = null;

    const animate = (timestamp) => {
      if (!this.animationActive) return;
      if (!startTime) startTime = timestamp;

      const phase = ((timestamp - startTime) / cycleDuration) % 1;

      try {
        if (this.map.getLayer(this.flowLayerId)) {
          // ~400m per dash; clamp to [4, 30] for visual consistency
          const numDashes = this.selectedTrackLength > 0
            ? Math.max(4, Math.min(30, Math.round(this.selectedTrackLength / 400)))
            : 6;

          // Transparent base when segments visible so their colors show through
          const baseColor = this.segmentsActive
            ? "rgba(255,255,255,0)"
            : undefined;

          this.map.setPaintProperty(
            this.flowLayerId,
            "line-gradient",
            this._buildFlowGradient(phase, { baseColor, numDashes }),
          );
        }
      } catch (e) {
        console.warn("[TracksLayer] Animation frame error:", e);
      }

      if (this.animationActive) {
        this.animationFrame = requestAnimationFrame(animate);
      }
    };

    this.animationFrame = requestAnimationFrame(animate);
  }

  /**
   * Stop the flowing gradient animation
   */
  _stopFlowAnimation() {
    this.animationActive = false;
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Compute the total length of a LineString in meters (haversine).
   * @param {Array} coordinates - Array of [lon, lat] pairs
   * @returns {number} Length in meters
   */
  _computeLineLength(coordinates) {
    const toRad = (deg) => (deg * Math.PI) / 180;
    let total = 0;
    for (let i = 1; i < coordinates.length; i++) {
      const [lon1, lat1] = coordinates[i - 1];
      const [lon2, lat2] = coordinates[i];
      const dLat = toRad(lat2 - lat1);
      const dLon = toRad(lon2 - lon1);
      const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
      total += 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
    return total;
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
      return;
    }

    if (!segments || segments.length === 0) {
      this.hideSegments();
      return;
    }

    const coords = trackFeature.geometry.coordinates;
    if (coords.length < 2) {
      return;
    }

    // Create line features for each segment
    const segmentFeatures = segments
      .map((segment, idx) => {
        const startIdx = Math.max(0, segment.start_index || 0);
        const endIdx = Math.min(
          coords.length - 1,
          (segment.end_index || startIdx) + 1,
        );

        // Extract coordinates for this segment
        const segmentCoords = coords.slice(startIdx, endIdx + 1);

        // Need at least 2 points for a line
        if (segmentCoords.length < 2) {
          return null;
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
        };
      })
      .filter(Boolean);

    const segmentGeoJSON = {
      type: "FeatureCollection",
      features: segmentFeatures,
    };

    // Add or update segment source and layer
    if (!this.map.getSource(this.segmentSourceId)) {
      this.map.addSource(this.segmentSourceId, {
        type: "geojson",
        data: segmentGeoJSON,
      });

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
      });

      // Set up hover events for segments
      this._setupSegmentHoverEvents();
    } else {
      this.map.getSource(this.segmentSourceId).setData(segmentGeoJSON);
      // Make sure layer is visible
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "visible");
    }

    // Move the flow layer on top of segments so dashes overlay the
    // transport-mode colors. The animation loop switches to a transparent
    // base when segmentsActive is true, letting segment colors show through.
    this.segmentsActive = true;
    if (this.map.getLayer(this.flowLayerId)) {
      this.map.moveLayer(this.flowLayerId);
    }

    // Dim the original track to highlight segments
    if (this.map.getLayer(this.id)) {
      this.map.setPaintProperty(this.id, "line-opacity", 0.3);
    }
  }

  /**
   * Hide segment highlighting
   */
  hideSegments() {
    this.segmentsActive = false;

    // Hide segment layer
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.setLayoutProperty(this.segmentLayerId, "visibility", "none");
    }

    // Restore original track opacity
    if (this.map.getLayer(this.id)) {
      this.map.setPaintProperty(this.id, "line-opacity", 0.7);
    }
  }

  /**
   * Set up hover event handlers for segment layer
   */
  _setupSegmentHoverEvents() {
    // Store bound handlers for later cleanup
    this._segmentMouseEnterHandler = (e) => {
      this.map.getCanvas().style.cursor = "pointer";

      if (e.features && e.features[0] && this.onSegmentHover) {
        const segmentIndex = e.features[0].properties.segmentIndex;
        this.onSegmentHover(segmentIndex);
      }
    };

    this._segmentMouseLeaveHandler = () => {
      this.map.getCanvas().style.cursor = "";

      if (this.onSegmentLeave) {
        this.onSegmentLeave();
      }
    };

    this.map.on("mouseenter", this.segmentLayerId, this._segmentMouseEnterHandler);
    this.map.on("mouseleave", this.segmentLayerId, this._segmentMouseLeaveHandler);
  }

  /**
   * Remove segment hover event handlers
   */
  _removeSegmentHoverEvents() {
    if (this._segmentMouseEnterHandler) {
      this.map.off("mouseenter", this.segmentLayerId, this._segmentMouseEnterHandler);
      this._segmentMouseEnterHandler = null;
    }
    if (this._segmentMouseLeaveHandler) {
      this.map.off("mouseleave", this.segmentLayerId, this._segmentMouseLeaveHandler);
      this._segmentMouseLeaveHandler = null;
    }
  }

  /**
   * Set callback for segment hover events
   * @param {Function} callback - Called with segmentIndex when hovering a segment
   */
  setSegmentHoverCallback(callback) {
    this.onSegmentHover = callback;
  }

  /**
   * Set callback for segment leave events
   * @param {Function} callback - Called when mouse leaves a segment
   */
  setSegmentLeaveCallback(callback) {
    this.onSegmentLeave = callback;
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
      console.warn("[TracksLayer] Cannot update track: invalid feature");
      return false;
    }

    const source = this.map.getSource(this.sourceId);
    if (!source) {
      console.warn("[TracksLayer] Cannot update track: source not found");
      return false;
    }

    // Get current data
    const currentData = this.data || source._data;
    if (!currentData || !currentData.features) {
      console.warn("[TracksLayer] Cannot update track: no data");
      return false;
    }

    // Find and update the track
    const trackId = trackFeature.properties.id;
    const featureIndex = currentData.features.findIndex(
      (f) => f.properties?.id === trackId,
    );

    if (featureIndex === -1) {
      console.warn(`[TracksLayer] Track ${trackId} not found in layer`);
      return false;
    }

    // Update the feature in place
    currentData.features[featureIndex] = trackFeature;

    // Update the source
    source.setData(currentData);

    // Also update our cached data reference
    this.data = currentData;

    // If this track has segments displayed, update them too
    if (options.preserveSelection && this.map.getSource(this.segmentSourceId)) {
      const segments = trackFeature.properties?.segments || [];
      const parsedSegments =
        typeof segments === "string" ? JSON.parse(segments) : segments;

      if (parsedSegments.length > 0) {
        this.showSegments(trackFeature, parsedSegments);
      }
    }

    console.log(`[TracksLayer] Updated track ${trackId}`);
    return trackFeature;
  }

  /**
   * Override remove to also clean up segment and selection layers
   */
  remove() {
    // Stop animation first
    this._stopFlowAnimation();

    // Remove segment event handlers
    this._removeSegmentHoverEvents();

    // Remove segment layer and source
    if (this.map.getLayer(this.segmentLayerId)) {
      this.map.removeLayer(this.segmentLayerId);
    }
    if (this.map.getSource(this.segmentSourceId)) {
      this.map.removeSource(this.segmentSourceId);
    }

    // Remove selection layers (border + flow)
    [this.flowLayerId, this.selectionBorderLayerId].forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId);
      }
    });

    // Remove selection source
    if (this.map.getSource(this.selectionSourceId)) {
      this.map.removeSource(this.selectionSourceId);
    }

    // Call parent remove
    super.remove();
  }
}
