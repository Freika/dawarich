import { createPolylinesLayer } from "./polylines";
import { createLiveMarker } from "./marker_factory";

/**
 * LiveMapHandler - Manages real-time GPS point streaming and live map updates
 *
 * This class handles the memory-efficient live mode functionality that was
 * previously causing memory leaks in the main maps controller.
 *
 * Features:
 * - Incremental marker addition (no layer recreation)
 * - Bounded data structures (prevents memory leaks)
 * - Efficient polyline segment updates
 * - Smart last marker tracking
 */
export class LiveMapHandler {
  constructor(map, layers, options = {}) {
    this.map = map;
    this.markersLayer = layers.markersLayer;
    this.polylinesLayer = layers.polylinesLayer;
    this.heatmapLayer = layers.heatmapLayer;
    this.fogOverlay = layers.fogOverlay;

    // Data arrays - can be initialized with existing data
    this.markers = options.existingMarkers || [];
    this.markersArray = options.existingMarkersArray || [];
    this.heatmapMarkers = options.existingHeatmapMarkers || [];

    // Configuration options
    this.maxPoints = options.maxPoints || 1000;
    this.routeOpacity = options.routeOpacity || 1;
    this.timezone = options.timezone || 'UTC';
    this.distanceUnit = options.distanceUnit || 'km';
    this.userSettings = options.userSettings || {};
    this.clearFogRadius = options.clearFogRadius || 100;
    this.fogLinethreshold = options.fogLinethreshold || 10;

    // State tracking
    this.isEnabled = false;
    this.lastMarkerRef = null;

    // Bind methods
    this.appendPoint = this.appendPoint.bind(this);
    this.enable = this.enable.bind(this);
    this.disable = this.disable.bind(this);
  }

  /**
   * Enable live mode
   */
  enable() {
    this.isEnabled = true;
    console.log('Live map mode enabled');
  }

  /**
   * Disable live mode and cleanup
   */
  disable() {
    this.isEnabled = false;
    this._cleanup();
    console.log('Live map mode disabled');
  }

  /**
   * Check if live mode is currently enabled
   */
  get enabled() {
    return this.isEnabled;
  }

  /**
   * Append a new GPS point to the live map (memory-efficient implementation)
   *
   * @param {Array} data - Point data [lat, lng, battery, altitude, timestamp, velocity, id, country]
   */
  appendPoint(data) {
    if (!this.isEnabled) {
      console.warn('LiveMapHandler: appendPoint called but live mode is not enabled');
      return;
    }

    // Parse the received point data
    const newPoint = data;

    // Add the new point to the markers array
    this.markers.push(newPoint);

    // Implement bounded markers array (keep only last maxPoints in live mode)
    this._enforcePointLimits();

    // Create and add new marker incrementally
    const newMarker = this._createMarker(newPoint);
    this.markersArray.push(newMarker);
    this.markersLayer.addLayer(newMarker);

    // Update heatmap with bounds
    this._updateHeatmap(newPoint);

    // Update polylines incrementally
    this._updatePolylines(newPoint);

    // Pan map to new location
    this.map.setView([newPoint[0], newPoint[1]], 16);

    // Update fog of war if enabled
    this._updateFogOfWar();

    // Update the last marker efficiently
    this._updateLastMarker();
  }

  /**
   * Get current statistics about the live map state
   */
  getStats() {
    return {
      totalPoints: this.markers.length,
      visibleMarkers: this.markersArray.length,
      heatmapPoints: this.heatmapMarkers.length,
      isEnabled: this.isEnabled,
      maxPoints: this.maxPoints
    };
  }

  /**
   * Update configuration options
   */
  updateOptions(newOptions) {
    Object.assign(this, newOptions);
  }

  /**
   * Clear all live mode data
   */
  clear() {
    // Clear data arrays
    this.markers = [];
    this.markersArray = [];
    this.heatmapMarkers = [];

    // Clear map layers
    this.markersLayer.clearLayers();
    this.polylinesLayer.clearLayers();
    this.heatmapLayer.setLatLngs([]);

    // Clear last marker reference
    if (this.lastMarkerRef) {
      this.map.removeLayer(this.lastMarkerRef);
      this.lastMarkerRef = null;
    }
  }

  // Private helper methods

  /**
   * Enforce point limits to prevent memory leaks
   * @private
   */
  _enforcePointLimits() {
    if (this.markers.length > this.maxPoints) {
      this.markers.shift(); // Remove oldest point

      // Also remove corresponding marker from display
      if (this.markersArray.length > this.maxPoints) {
        const oldMarker = this.markersArray.shift();
        this.markersLayer.removeLayer(oldMarker);
      }
    }
  }

  /**
   * Create a new marker using the shared factory (memory-efficient for live streaming)
   * @private
   */
  _createMarker(point) {
    return createLiveMarker(point);
  }

  /**
   * Update heatmap with bounded data
   * @private
   */
  _updateHeatmap(point) {
    this.heatmapMarkers.push([point[0], point[1], 0.2]);

    // Keep heatmap bounded
    if (this.heatmapMarkers.length > this.maxPoints) {
      this.heatmapMarkers.shift(); // Remove oldest point
    }

    this.heatmapLayer.setLatLngs(this.heatmapMarkers);
  }

  /**
   * Update polylines incrementally (only add new segments)
   * @private
   */
  _updatePolylines(newPoint) {
    // Only update polylines if we have more than one point
    if (this.markers.length > 1) {
      const prevPoint = this.markers[this.markers.length - 2];
      const newSegment = L.polyline([
        [prevPoint[0], prevPoint[1]],
        [newPoint[0], newPoint[1]]
      ], {
        color: this.routeOpacity > 0 ? '#3388ff' : 'transparent',
        weight: 3,
        opacity: this.routeOpacity
      });

      // Add only the new segment instead of recreating all polylines
      this.polylinesLayer.addLayer(newSegment);
    }
  }

  /**
   * Update fog of war if enabled
   * @private
   */
  _updateFogOfWar() {
    if (this.map.hasLayer(this.fogOverlay)) {
      // This would need to be implemented based on the existing fog logic
      // For now, we'll just log that it needs updating
      console.log('LiveMapHandler: Fog of war update needed');
    }
  }

  /**
   * Update the last marker efficiently using direct reference tracking
   * @private
   */
  _updateLastMarker() {
    // Remove previous last marker
    if (this.lastMarkerRef) {
      this.map.removeLayer(this.lastMarkerRef);
    }

    // Add new last marker and store reference
    if (this.markers.length > 0) {
      const lastPoint = this.markers[this.markers.length - 1];
      const lastMarker = L.marker([lastPoint[0], lastPoint[1]]);
      this.lastMarkerRef = lastMarker.addTo(this.map);
    }
  }

  /**
   * Cleanup resources when disabling live mode
   * @private
   */
  _cleanup() {
    // Remove last marker
    if (this.lastMarkerRef) {
      this.map.removeLayer(this.lastMarkerRef);
      this.lastMarkerRef = null;
    }

    // Note: We don't clear the data arrays here as the user might want to keep
    // the points visible after disabling live mode. Use clear() for that.
  }
}
