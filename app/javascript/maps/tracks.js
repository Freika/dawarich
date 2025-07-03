import { formatDate } from "../maps/helpers";
import { formatDistance } from "../maps/helpers";
import { formatSpeed } from "../maps/helpers";
import { minutesToDaysHoursMinutes } from "../maps/helpers";

// Track-specific color palette - different from regular polylines
export const trackColorPalette = {
  default: 'blue',      // Green - distinct from blue polylines
  hover: '#FF6B35',        // Orange-red for hover
  active: '#E74C3C',       // Red for active/clicked
  start: '#2ECC71',        // Green for start marker
  end: '#E67E22'           // Orange for end marker
};

export function getTrackColor() {
  // All tracks use the same default color
  return trackColorPalette.default;
}

export function createTrackPopupContent(track, distanceUnit) {
  const startTime = formatDate(track.start_at, 'UTC');
  const endTime = formatDate(track.end_at, 'UTC');
  const duration = track.duration || 0;
  const durationFormatted = minutesToDaysHoursMinutes(Math.round(duration / 60));

  return `
    <div class="track-popup">
      <h4 class="track-popup-title">📍 Track #${track.id}</h4>
      <div class="track-info">
        <strong>🕐 Start:</strong> ${startTime}<br>
        <strong>🏁 End:</strong> ${endTime}<br>
        <strong>⏱️ Duration:</strong> ${durationFormatted}<br>
        <strong>📏 Distance:</strong> ${formatDistance(track.distance / 1000, distanceUnit)}<br>
        <strong>⚡ Avg Speed:</strong> ${formatSpeed(track.avg_speed, distanceUnit)}<br>
        <strong>⛰️ Elevation:</strong> +${track.elevation_gain || 0}m / -${track.elevation_loss || 0}m<br>
        <strong>📊 Max Alt:</strong> ${track.elevation_max || 0}m<br>
        <strong>📉 Min Alt:</strong> ${track.elevation_min || 0}m
      </div>
    </div>
  `;
}

export function addTrackInteractions(trackGroup, map, track, userSettings, distanceUnit) {
  let hoverPopup = null;
  let isClicked = false;

  // Create start and end markers
  const startIcon = L.divIcon({
    html: "🚀",
    className: "track-start-icon emoji-icon",
    iconSize: [20, 20]
  });

  const endIcon = L.divIcon({
    html: "🎯",
    className: "track-end-icon emoji-icon",
    iconSize: [20, 20]
  });

  // Get first and last coordinates from the track path
  const coordinates = getTrackCoordinates(track);
  if (!coordinates || coordinates.length < 2) return;

  const startCoord = coordinates[0];
  const endCoord = coordinates[coordinates.length - 1];

  const startMarker = L.marker([startCoord[0], startCoord[1]], { icon: startIcon });
  const endMarker = L.marker([endCoord[0], endCoord[1]], { icon: endIcon });

  function handleTrackHover(e) {
    if (isClicked) return; // Don't change hover state if clicked

    // Apply hover style to all segments in the track
    trackGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({
          color: trackColorPalette.hover,
          weight: 6,
          opacity: 0.9
        });
        layer.bringToFront();
      }
    });

    // Show markers and popup
    startMarker.addTo(map);
    endMarker.addTo(map);

    const popupContent = createTrackPopupContent(track, distanceUnit);

    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }

    hoverPopup = L.popup()
      .setLatLng(e.latlng)
      .setContent(popupContent)
      .addTo(map);
  }

  function handleTrackMouseOut(e) {
    if (isClicked) return; // Don't reset if clicked

    // Reset to original style
    trackGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({
          color: layer.options.originalColor,
          weight: 4,
          opacity: userSettings.route_opacity || 0.7
        });
      }
    });

    // Remove markers and popup
    if (hoverPopup) {
      map.closePopup(hoverPopup);
      map.removeLayer(startMarker);
      map.removeLayer(endMarker);
    }
  }

  function handleTrackClick(e) {
    e.originalEvent.stopPropagation();

    // Toggle clicked state
    isClicked = !isClicked;

    if (isClicked) {
      // Apply clicked style
      trackGroup.eachLayer((layer) => {
        if (layer instanceof L.Polyline) {
          layer.setStyle({
            color: trackColorPalette.active,
            weight: 8,
            opacity: 1
          });
          layer.bringToFront();
        }
      });

      startMarker.addTo(map);
      endMarker.addTo(map);

      // Show persistent popup
      const popupContent = createTrackPopupContent(track, distanceUnit);

      L.popup()
        .setLatLng(e.latlng)
        .setContent(popupContent)
        .addTo(map);

      // Store reference for cleanup
      trackGroup._isTrackClicked = true;
      trackGroup._trackStartMarker = startMarker;
      trackGroup._trackEndMarker = endMarker;
    } else {
      // Reset to hover state or original state
      handleTrackMouseOut(e);
      trackGroup._isTrackClicked = false;
      if (trackGroup._trackStartMarker) map.removeLayer(trackGroup._trackStartMarker);
      if (trackGroup._trackEndMarker) map.removeLayer(trackGroup._trackEndMarker);
    }
  }

  // Add event listeners to all layers in the track group
  trackGroup.eachLayer((layer) => {
    if (layer instanceof L.Polyline) {
      layer.on('mouseover', handleTrackHover);
      layer.on('mouseout', handleTrackMouseOut);
      layer.on('click', handleTrackClick);
    }
  });

  // Reset when clicking elsewhere on map
  map.on('click', function() {
    if (trackGroup._isTrackClicked) {
      isClicked = false;
      trackGroup._isTrackClicked = false;
      handleTrackMouseOut({ latlng: [0, 0] });
      if (trackGroup._trackStartMarker) map.removeLayer(trackGroup._trackStartMarker);
      if (trackGroup._trackEndMarker) map.removeLayer(trackGroup._trackEndMarker);
    }
  });
}

function getTrackCoordinates(track) {
  // Add debugging to see what we're working with
  console.log(`DEBUG: Parsing track ${track.id}:`, {
    has_coordinates: !!(track.coordinates && Array.isArray(track.coordinates)),
    has_path: !!(track.path && Array.isArray(track.path)),
    original_path_type: typeof track.original_path,
    original_path_length: track.original_path ? track.original_path.length : 0,
    original_path_sample: track.original_path ? track.original_path.substring(0, 100) + '...' : null
  });

  // First check if coordinates are already provided as an array
  if (track.coordinates && Array.isArray(track.coordinates)) {
    console.log(`DEBUG: Using coordinates array for track ${track.id}`);
    return track.coordinates; // If already provided as array of [lat, lng]
  }

  // If coordinates are provided as a path property
  if (track.path && Array.isArray(track.path)) {
    console.log(`DEBUG: Using path array for track ${track.id}`);
    return track.path;
  }

  // Try to parse from original_path (PostGIS LineString format)
  if (track.original_path && typeof track.original_path === 'string') {
    try {
      console.log(`DEBUG: Attempting to parse original_path for track ${track.id}: "${track.original_path}"`);

      // Parse PostGIS LineString format: "LINESTRING (lng lat, lng lat, ...)" or "LINESTRING(lng lat, lng lat, ...)"
      const match = track.original_path.match(/LINESTRING\s*\(([^)]+)\)/i);
      if (match) {
        console.log(`DEBUG: LineString match found for track ${track.id}: "${match[1]}"`);
        const coordString = match[1];
        const coordinates = coordString.split(',').map(pair => {
          const [lng, lat] = pair.trim().split(/\s+/).map(parseFloat);
          if (isNaN(lng) || isNaN(lat)) {
            console.warn(`Invalid coordinates in track ${track.id}: "${pair.trim()}"`);
            return null;
          }
          return [lat, lng]; // Return as [lat, lng] for Leaflet
        }).filter(Boolean); // Remove null entries

        console.log(`DEBUG: Parsed ${coordinates.length} coordinates for track ${track.id}`);

        if (coordinates.length >= 2) {
        return coordinates;
        } else {
          console.warn(`Track ${track.id} has only ${coordinates.length} valid coordinates`);
        }
      } else {
        console.warn(`No LINESTRING match found for track ${track.id}. Raw: "${track.original_path}"`);
      }
    } catch (error) {
      console.error(`Failed to parse track original_path for track ${track.id}:`, error);
      console.error(`Raw original_path: "${track.original_path}"`);
    }
  }

  // For development/testing, create a simple line if we have start/end coordinates
  if (track.start_point && track.end_point) {
    console.log(`DEBUG: Using start/end points for track ${track.id}`);
    return [
      [track.start_point.lat, track.start_point.lng],
      [track.end_point.lat, track.end_point.lng]
    ];
  }

  console.warn('Track coordinates not available for track', track.id);
  return [];
}

export function createTracksLayer(tracks, map, userSettings, distanceUnit) {
  // Create a custom pane for tracks with higher z-index than regular polylines
  if (!map.getPane('tracksPane')) {
    map.createPane('tracksPane');
    map.getPane('tracksPane').style.zIndex = 460; // Above polylines pane (450)
  }

  const renderer = L.canvas({
    padding: 0.5,
    pane: 'tracksPane'
  });

  const trackLayers = tracks.map((track) => {
    const coordinates = getTrackCoordinates(track);

    if (!coordinates || coordinates.length < 2) {
      console.warn(`Track ${track.id} has insufficient coordinates`);
      return null;
    }

    const trackColor = getTrackColor();
    const trackGroup = L.featureGroup();

    // Create polyline segments for the track
    // For now, create a single polyline, but this could be segmented for elevation/speed coloring
    const trackPolyline = L.polyline(coordinates, {
      renderer: renderer,
      color: trackColor,
      originalColor: trackColor,
      opacity: userSettings.route_opacity || 0.7,
      weight: 4,
      interactive: true,
      pane: 'tracksPane',
      bubblingMouseEvents: false,
      trackId: track.id
    });

    trackGroup.addLayer(trackPolyline);

    // Add interactions
    addTrackInteractions(trackGroup, map, track, userSettings, distanceUnit);

    // Store track data for reference
    trackGroup._trackData = track;

    return trackGroup;
  }).filter(Boolean); // Remove null entries

  // Create the main layer group
  const tracksLayerGroup = L.layerGroup(trackLayers);

  // Add CSS for track styling
  const style = document.createElement('style');
  style.textContent = `
    .leaflet-tracksPane-pane {
      pointer-events: auto !important;
    }
    .leaflet-tracksPane-pane canvas {
      pointer-events: auto !important;
    }
    .track-popup {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    .track-popup-title {
      margin: 0 0 8px 0;
      color: #2c3e50;
      font-size: 16px;
    }
    .track-info {
      font-size: 13px;
      line-height: 1.4;
    }
    .track-start-icon, .track-end-icon {
      font-size: 16px;
    }
  `;
  document.head.appendChild(style);

  return tracksLayerGroup;
}

export function updateTracksColors(tracksLayer) {
  const defaultColor = getTrackColor();

  tracksLayer.eachLayer((trackGroup) => {
    trackGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({
          color: defaultColor,
          originalColor: defaultColor
        });
      }
    });
  });
}

export function updateTracksOpacity(tracksLayer, opacity) {
  tracksLayer.eachLayer((trackGroup) => {
    trackGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({ opacity: opacity });
      }
    });
  });
}

export function toggleTracksVisibility(tracksLayer, map, isVisible) {
  if (isVisible && !map.hasLayer(tracksLayer)) {
    tracksLayer.addTo(map);
  } else if (!isVisible && map.hasLayer(tracksLayer)) {
    map.removeLayer(tracksLayer);
  }
}

// Helper function to filter tracks by criteria
export function filterTracks(tracks, criteria) {
  return tracks.filter(track => {
    if (criteria.minDistance && track.distance < criteria.minDistance * 1000) return false;
    if (criteria.maxDistance && track.distance > criteria.maxDistance * 1000) return false;
    if (criteria.minDuration && track.duration < criteria.minDuration * 60) return false;
    if (criteria.maxDuration && track.duration > criteria.maxDuration * 60) return false;
    if (criteria.startDate && new Date(track.start_at) < new Date(criteria.startDate)) return false;
    if (criteria.endDate && new Date(track.end_at) > new Date(criteria.endDate)) return false;
    return true;
  });
}
