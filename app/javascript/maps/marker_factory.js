import { createPopupContent } from "./popups";

const MARKER_DATA_INDICES = {
  LATITUDE: 0,
  LONGITUDE: 1,
  BATTERY: 2,
  ALTITUDE: 3,
  TIMESTAMP: 4,
  VELOCITY: 5,
  ID: 6,
  COUNTRY: 7
};

/**
 * MarkerFactory - Centralized marker creation with consistent styling
 *
 * This module provides reusable marker creation functions to ensure
 * consistent styling and prevent code duplication between different
 * map components.
 *
 * Memory-safe: Creates fresh instances, no shared references that could
 * cause memory leaks.
 */

/**
 * Create a standard divIcon for GPS points
 * @param {string} color - Marker color ('blue', 'orange', etc.)
 * @param {number} size - Icon size in pixels (default: 8)
 * @returns {L.DivIcon} Leaflet divIcon instance
 */
export function createStandardIcon(color = 'blue', size = 4) {
  return L.divIcon({
    className: 'custom-div-icon',
    html: `<div style='background-color: ${color}; width: ${size}px; height: ${size}px; border-radius: 50%;'></div>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2]
  });
}

/**
 * Create a basic marker for live streaming (no drag handlers, minimal features)
 * Memory-efficient for high-frequency creation/destruction
 *
 * @param {Array} point - Point data [lat, lng, battery, altitude, timestamp, velocity, id, country]
 * @param {Object} options - Optional marker configuration
 * @returns {L.Marker} Leaflet marker instance
 */
export function createLiveMarker(point, options = {}) {
  const [lat, lng] = point;
  const velocity = point[5] || 0; // velocity is at index 5
  const markerColor = velocity < 0 ? 'orange' : 'blue';
  const size = options.size || 8;

  return L.marker([lat, lng], {
    icon: createStandardIcon(markerColor, size),
    // Live markers don't need these heavy features
    draggable: false,
    autoPan: false,
    // Store minimal data needed for cleanup
    pointId: point[6], // ID is at index 6
    ...options // Allow overriding defaults
  });
}

/**
 * Create a full-featured marker with drag handlers and popups
 * Used for static map display where full interactivity is needed
 *
 * @param {Array} point - Point data [lat, lng, battery, altitude, timestamp, velocity, id, country]
 * @param {number} index - Marker index in the array
 * @param {Object} userSettings - User configuration
 * @param {string} apiKey - API key for backend operations
 * @param {L.Renderer} renderer - Optional Leaflet renderer
 * @returns {L.Marker} Fully configured Leaflet marker with event handlers
 */
export function createInteractiveMarker(point, index, userSettings, apiKey, renderer = null) {
  const [lat, lng] = point;
  const pointId = point[6]; // ID is at index 6
  const velocity = point[5] || 0; // velocity is at index 5
  const markerColor = velocity < 0 ? 'orange' : 'blue';

  const marker = L.marker([lat, lng], {
    icon: createStandardIcon(markerColor),
    draggable: true,
    autoPan: true,
    pointIndex: index,
    pointId: pointId,
    originalLat: lat,
    originalLng: lng,
    markerData: point, // Store the complete marker data
    renderer: renderer
  });

  // Add popup
  marker.bindPopup(createPopupContent(point, userSettings.timezone, userSettings.distanceUnit));

  // Add drag event handlers
  addDragHandlers(marker, apiKey, userSettings);

  return marker;
}

/**
 * Create a simplified marker with minimal features
 * Used for simplified rendering mode
 *
 * @param {Array} point - Point data [lat, lng, battery, altitude, timestamp, velocity, id, country]
 * @param {Object} userSettings - User configuration (optional)
 * @returns {L.Marker} Leaflet marker with basic drag support
 */
export function createSimplifiedMarker(point, userSettings = {}) {
  const [lat, lng] = point;
  const velocity = point[5] || 0;
  const markerColor = velocity < 0 ? 'orange' : 'blue';

  const marker = L.marker([lat, lng], {
    icon: createStandardIcon(markerColor),
    draggable: true,
    autoPan: true
  });

  // Add popup if user settings provided
  if (userSettings.timezone && userSettings.distanceUnit) {
    marker.bindPopup(createPopupContent(point, userSettings.timezone, userSettings.distanceUnit));
  }

  // Add simple drag handlers
  marker.on('dragstart', function() {
    this.closePopup();
  });

  marker.on('dragend', function(e) {
    const newLatLng = e.target.getLatLng();
    this.setLatLng(newLatLng);
    this.openPopup();
  });

  return marker;
}

/**
 * Add comprehensive drag handlers to a marker
 * Handles polyline updates and backend synchronization
 *
 * @param {L.Marker} marker - The marker to add handlers to
 * @param {string} apiKey - API key for backend operations
 * @param {Object} userSettings - User configuration
 * @private
 */
function addDragHandlers(marker, apiKey, userSettings) {
  marker.on('dragstart', function(e) {
    this.closePopup();
  });

  marker.on('drag', function(e) {
    const newLatLng = e.target.getLatLng();
    const map = e.target._map;
    const pointIndex = e.target.options.pointIndex;
    const originalLat = e.target.options.originalLat;
    const originalLng = e.target.options.originalLng;

    // Find polylines by iterating through all map layers
    map.eachLayer((layer) => {
      // Check if this is a LayerGroup containing polylines
      if (layer instanceof L.LayerGroup) {
        layer.eachLayer((featureGroup) => {
          if (featureGroup instanceof L.FeatureGroup) {
            featureGroup.eachLayer((segment) => {
              if (segment instanceof L.Polyline) {
                const coords = segment.getLatLngs();
                const tolerance = 0.0000001;
                let updated = false;

                // Check and update start point
                if (Math.abs(coords[0].lat - originalLat) < tolerance &&
                    Math.abs(coords[0].lng - originalLng) < tolerance) {
                  coords[0] = newLatLng;
                  updated = true;
                }

                // Check and update end point
                if (Math.abs(coords[1].lat - originalLat) < tolerance &&
                    Math.abs(coords[1].lng - originalLng) < tolerance) {
                  coords[1] = newLatLng;
                  updated = true;
                }

                // Only update if we found a matching endpoint
                if (updated) {
                  segment.setLatLngs(coords);
                  segment.redraw();
                }
              }
            });
          }
        });
      }
    });

    // Update the marker's original position for the next drag event
    e.target.options.originalLat = newLatLng.lat;
    e.target.options.originalLng = newLatLng.lng;
  });

  marker.on('dragend', function(e) {
    const newLatLng = e.target.getLatLng();
    const pointId = e.target.options.pointId;
    const pointIndex = e.target.options.pointIndex;
    const originalMarkerData = e.target.options.markerData;

    fetch(`/api/v1/points/${pointId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        point: {
          latitude: newLatLng.lat.toString(),
          longitude: newLatLng.lng.toString()
        }
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      const map = e.target._map;
      if (map && map.mapsController && map.mapsController.markers) {
        const markers = map.mapsController.markers;
        if (markers[pointIndex]) {
          markers[pointIndex][0] = parseFloat(data.latitude);
          markers[pointIndex][1] = parseFloat(data.longitude);
        }
      }

      // Create updated marker data array
      const updatedMarkerData = [
        parseFloat(data.latitude),
        parseFloat(data.longitude),
        originalMarkerData[MARKER_DATA_INDICES.BATTERY],
        originalMarkerData[MARKER_DATA_INDICES.ALTITUDE],
        originalMarkerData[MARKER_DATA_INDICES.TIMESTAMP],
        originalMarkerData[MARKER_DATA_INDICES.VELOCITY],
        data.id,
        originalMarkerData[MARKER_DATA_INDICES.COUNTRY]
      ];

      // Update the marker's stored data
      e.target.options.markerData = updatedMarkerData;

      // Update the popup content
      if (this._popup) {
        const updatedPopupContent = createPopupContent(
          updatedMarkerData,
          userSettings.timezone,
          userSettings.distanceUnit
        );
        this.setPopupContent(updatedPopupContent);
      }
    })
    .catch(error => {
      console.error('Error updating point:', error);
      this.setLatLng([e.target.options.originalLat, e.target.options.originalLng]);
      alert('Failed to update point position. Please try again.');
    });
  });
}
