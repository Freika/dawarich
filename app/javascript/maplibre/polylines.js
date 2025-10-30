// MapLibre Polylines Implementation
// Business logic ported from maps/polylines.js

import {
  formatDate,
  formatDistance,
  formatSpeed,
  minutesToDaysHoursMinutes,
  haversineDistance
} from "./helpers";

// Import speed color utilities from Leaflet module (reusable logic)
import {
  calculateSpeed,
  getSpeedColor,
  colorStopsFallback,
  colorFormatEncode,
  colorFormatDecode
} from "../maps/polylines";

/**
 * Split markers into separate routes based on distance and time thresholds
 * @param {Array} markers - Array of GPS points [lat, lng, battery, altitude, timestamp, velocity, id, country]
 * @param {Object} userSettings - User settings with thresholds
 * @returns {Array} Array of route segments
 */
function splitRoutesIntoSegments(markers, userSettings) {
  const splitPolylines = [];
  let currentPolyline = [];

  const distanceThresholdMeters = parseInt(userSettings.meters_between_routes) || 500;
  const timeThresholdMinutes = parseInt(userSettings.minutes_between_routes) || 60;

  for (let i = 0, len = markers.length; i < len; i++) {
    if (currentPolyline.length === 0) {
      currentPolyline.push(markers[i]);
    } else {
      const lastPoint = currentPolyline[currentPolyline.length - 1];
      const currentPoint = markers[i];

      // Calculate distance in meters (haversineDistance returns km)
      const distance = haversineDistance(
        lastPoint[0], lastPoint[1],
        currentPoint[0], currentPoint[1]
      ) * 1000; // Convert km to meters

      const timeDifference = (currentPoint[4] - lastPoint[4]) / 60; // Convert to minutes

      // Split route if threshold exceeded
      if (distance > distanceThresholdMeters || timeDifference > timeThresholdMinutes) {
        splitPolylines.push([...currentPolyline]);
        currentPolyline = [currentPoint];
      } else {
        currentPolyline.push(currentPoint);
      }
    }
  }

  if (currentPolyline.length > 0) {
    splitPolylines.push(currentPolyline);
  }

  return splitPolylines;
}

/**
 * Create GeoJSON LineString features for all route segments
 * @param {Array} routeSegments - Split route segments
 * @param {Object} userSettings - User settings for styling
 * @returns {Object} GeoJSON FeatureCollection
 */
function createRoutesGeoJSON(routeSegments, userSettings) {
  const features = [];

  routeSegments.forEach((segment, segmentIndex) => {
    // Create individual line segments for speed coloring
    for (let i = 0; i < segment.length - 1; i++) {
      const point1 = segment[i];
      const point2 = segment[i + 1];

      // Calculate speed between points
      const speed = calculateSpeed(point1, point2);

      // Get color based on speed
      const color = getSpeedColor(
        speed,
        userSettings.speed_colored_routes,
        userSettings.speed_color_scale
      );

      // Create line segment feature
      const feature = {
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates: [
            [point1[1], point1[0]], // [lng, lat]
            [point2[1], point2[0]]
          ]
        },
        properties: {
          segmentIndex,
          pointIndex: i,
          speed,
          color,
          timestamp1: point1[4],
          timestamp2: point2[4],
          battery1: point1[2],
          battery2: point2[2],
          altitude1: point1[3],
          altitude2: point1[3]
        }
      };

      features.push(feature);
    }
  });

  return {
    type: 'FeatureCollection',
    features
  };
}

/**
 * Create route metadata for popups and interactions
 * @param {Array} routeSegments - Split route segments
 * @param {Object} userSettings - User settings
 * @param {String} distanceUnit - km or mi
 * @returns {Array} Array of route metadata
 */
function createRouteMetadata(routeSegments, userSettings, distanceUnit) {
  return routeSegments.map((segment) => {
    if (segment.length < 2) return null;

    const startPoint = segment[0];
    const endPoint = segment[segment.length - 1];

    // Calculate total distance
    const totalDistance = segment.reduce((acc, curr, index, arr) => {
      if (index === 0) return acc;
      const dist = haversineDistance(
        arr[index - 1][0], arr[index - 1][1],
        curr[0], curr[1]
      );
      return acc + dist;
    }, 0);

    // Calculate duration
    const durationSeconds = endPoint[4] - startPoint[4];
    const durationMinutes = Math.round(durationSeconds / 60);

    return {
      startPoint,
      endPoint,
      startTimestamp: formatDate(startPoint[4], userSettings.timezone),
      endTimestamp: formatDate(endPoint[4], userSettings.timezone),
      duration: minutesToDaysHoursMinutes(durationMinutes),
      totalDistance: formatDistance(totalDistance, distanceUnit),
      totalDistanceKm: totalDistance,
      coordinates: segment.map(p => [p[1], p[0]]) // [lng, lat]
    };
  }).filter(Boolean);
}

/**
 * Add polylines layer to MapLibre map
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Array} markers - GPS points array
 * @param {Object} userSettings - User settings
 * @param {String} distanceUnit - Distance unit (km/mi)
 * @returns {Object} Layer info for management
 */
export function addPolylinesLayer(map, markers, userSettings, distanceUnit) {
  console.log('Adding polylines layer with', markers.length, 'points');

  if (!markers || markers.length < 2) {
    console.warn('Not enough markers for polylines');
    return null;
  }

  // Split routes into segments
  const routeSegments = splitRoutesIntoSegments(markers, userSettings);
  console.log('Created', routeSegments.length, 'route segments');

  // Create GeoJSON for routes
  const routesGeoJSON = createRoutesGeoJSON(routeSegments, userSettings);

  // Create metadata for interactions
  const routeMetadata = createRouteMetadata(routeSegments, userSettings, distanceUnit);

  // Get route opacity from settings
  const routeOpacity = parseFloat(userSettings.route_opacity) || 0.6;

  // Add source
  map.addSource('routes', {
    type: 'geojson',
    data: routesGeoJSON,
    lineMetrics: true // Enable line metrics for advanced styling
  });

  // Add line layer
  map.addLayer({
    id: 'routes-layer',
    type: 'line',
    source: 'routes',
    layout: {
      'line-join': 'round',
      'line-cap': 'round'
    },
    paint: {
      'line-color': ['get', 'color'], // Use color from feature properties
      'line-width': 3,
      'line-opacity': routeOpacity
    }
  });

  // Add hover layer (wider line on top)
  map.addLayer({
    id: 'routes-hover',
    type: 'line',
    source: 'routes',
    layout: {
      'line-join': 'round',
      'line-cap': 'round'
    },
    paint: {
      'line-color': ['get', 'color'],
      'line-width': 8,
      'line-opacity': 0 // Hidden by default, shown on hover
    }
  });

  // Store metadata for event handlers
  map._routeMetadata = routeMetadata;
  map._routeSegments = routeSegments;

  console.log('Polylines layer added successfully');

  return {
    sourceId: 'routes',
    layerId: 'routes-layer',
    hoverLayerId: 'routes-hover',
    metadata: routeMetadata
  };
}

/**
 * Setup polyline interactions (hover, click)
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Object} userSettings - User settings
 * @param {String} distanceUnit - Distance unit
 */
export function setupPolylineInteractions(map, userSettings, distanceUnit) {
  let hoveredSegmentIndex = null;
  let clickedSegmentIndex = null;
  let popup = null;
  let startMarker = null;
  let endMarker = null;

  // Change cursor on hover
  map.on('mouseenter', 'routes-layer', () => {
    map.getCanvas().style.cursor = 'pointer';
  });

  map.on('mouseleave', 'routes-layer', () => {
    map.getCanvas().style.cursor = '';
  });

  // Handle hover
  map.on('mousemove', 'routes-layer', (e) => {
    if (e.features.length === 0) return;

    const feature = e.features[0];
    const segmentIndex = feature.properties.segmentIndex;

    // Don't update hover if this segment is clicked
    if (clickedSegmentIndex === segmentIndex) return;

    // Update hover state
    if (hoveredSegmentIndex !== segmentIndex) {
      // Clear previous hover
      if (hoveredSegmentIndex !== null && hoveredSegmentIndex !== clickedSegmentIndex) {
        map.setPaintProperty('routes-hover', 'line-opacity', [
          'case',
          ['==', ['get', 'segmentIndex'], hoveredSegmentIndex],
          0,
          ['get-paint', 'routes-hover', 'line-opacity']
        ]);
      }

      hoveredSegmentIndex = segmentIndex;

      // Highlight hovered segment
      map.setPaintProperty('routes-hover', 'line-opacity', [
        'case',
        ['==', ['get', 'segmentIndex'], segmentIndex],
        1,
        ['==', ['get', 'segmentIndex'], clickedSegmentIndex],
        1,
        0
      ]);
    }

    // Show popup on hover
    if (!popup && clickedSegmentIndex === null) {
      showRoutePopup(map, e.lngLat, segmentIndex, userSettings, distanceUnit);
    }
  });

  // Handle mouse leave
  map.on('mouseleave', 'routes-layer', () => {
    // Clear hover if not clicked
    if (clickedSegmentIndex === null) {
      map.setPaintProperty('routes-hover', 'line-opacity', 0);
      hoveredSegmentIndex = null;

      if (popup) {
        popup.remove();
        popup = null;
      }

      removeMarkers();
    }
  });

  // Handle click
  map.on('click', 'routes-layer', (e) => {
    if (e.features.length === 0) return;

    const feature = e.features[0];
    const segmentIndex = feature.properties.segmentIndex;

    // Toggle click state
    if (clickedSegmentIndex === segmentIndex) {
      // Unclick
      clickedSegmentIndex = null;
      map.setPaintProperty('routes-hover', 'line-opacity', 0);

      if (popup) {
        popup.remove();
        popup = null;
      }

      removeMarkers();
    } else {
      // Click new segment
      clickedSegmentIndex = segmentIndex;

      // Highlight clicked segment
      map.setPaintProperty('routes-hover', 'line-opacity', [
        'case',
        ['==', ['get', 'segmentIndex'], segmentIndex],
        1,
        0
      ]);

      // Show persistent popup
      showRoutePopup(map, e.lngLat, segmentIndex, userSettings, distanceUnit, true);
    }

    e.preventDefault();
  });

  // Clear click when clicking map background
  map.on('click', (e) => {
    // Only clear if not clicking on a route
    if (e.originalEvent.target.tagName !== 'CANVAS') return;

    const features = map.queryRenderedFeatures(e.point, {
      layers: ['routes-layer']
    });

    if (features.length === 0 && clickedSegmentIndex !== null) {
      clickedSegmentIndex = null;
      map.setPaintProperty('routes-hover', 'line-opacity', 0);

      if (popup) {
        popup.remove();
        popup = null;
      }

      removeMarkers();
    }
  });

  // Helper to show route popup
  function showRoutePopup(map, lngLat, segmentIndex, userSettings, distanceUnit, persistent = false) {
    const metadata = map._routeMetadata[segmentIndex];
    if (!metadata) return;

    // Add start/end markers
    if (startMarker) startMarker.remove();
    if (endMarker) endMarker.remove();

    startMarker = new maplibregl.Marker({ color: '#00ff00' })
      .setLngLat(metadata.coordinates[0])
      .addTo(map);

    endMarker = new maplibregl.Marker({ color: '#ff0000' })
      .setLngLat(metadata.coordinates[metadata.coordinates.length - 1])
      .addTo(map);

    // Create popup content
    const popupContent = `
      <div style="padding: 8px;">
        <div style="margin-bottom: 4px;"><strong>Start:</strong> ${metadata.startTimestamp}</div>
        <div style="margin-bottom: 4px;"><strong>End:</strong> ${metadata.endTimestamp}</div>
        <div style="margin-bottom: 4px;"><strong>Duration:</strong> ${metadata.duration}</div>
        <div style="margin-bottom: 4px;"><strong>Distance:</strong> ${metadata.totalDistance}</div>
      </div>
    `;

    if (popup) {
      popup.remove();
    }

    popup = new maplibregl.Popup({
      closeButton: persistent,
      closeOnClick: !persistent,
      closeOnMove: !persistent
    })
      .setLngLat(lngLat)
      .setHTML(popupContent)
      .addTo(map);

    if (persistent) {
      popup.on('close', () => {
        clickedSegmentIndex = null;
        map.setPaintProperty('routes-hover', 'line-opacity', 0);
        removeMarkers();
      });
    }
  }

  function removeMarkers() {
    if (startMarker) {
      startMarker.remove();
      startMarker = null;
    }
    if (endMarker) {
      endMarker.remove();
      endMarker = null;
    }
  }
}

/**
 * Update polylines opacity
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Number} opacity - New opacity value (0-1)
 */
export function updatePolylinesOpacity(map, opacity) {
  if (!map.getLayer('routes-layer')) return;

  map.setPaintProperty('routes-layer', 'line-opacity', opacity);
  console.log('Updated polylines opacity to', opacity);
}

/**
 * Update polylines colors (when speed color settings change)
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Array} markers - GPS points
 * @param {Object} userSettings - Updated user settings
 */
export function updatePolylinesColors(map, markers, userSettings) {
  if (!map.getSource('routes')) return;

  console.log('Updating polylines colors');

  // Recreate GeoJSON with new colors
  const routeSegments = splitRoutesIntoSegments(markers, userSettings);
  const routesGeoJSON = createRoutesGeoJSON(routeSegments, userSettings);

  // Update source data
  map.getSource('routes').setData(routesGeoJSON);

  console.log('Polylines colors updated');
}

/**
 * Remove polylines layer from map
 * @param {maplibregl.Map} map - MapLibre map instance
 */
export function removePolylinesLayer(map) {
  if (map.getLayer('routes-hover')) {
    map.removeLayer('routes-hover');
  }
  if (map.getLayer('routes-layer')) {
    map.removeLayer('routes-layer');
  }
  if (map.getSource('routes')) {
    map.removeSource('routes');
  }

  // Clean up metadata
  delete map._routeMetadata;
  delete map._routeSegments;

  console.log('Polylines layer removed');
}
