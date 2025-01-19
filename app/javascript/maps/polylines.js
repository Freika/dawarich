import { formatDate } from "../maps/helpers";
import { formatDistance } from "../maps/helpers";
import { minutesToDaysHoursMinutes } from "../maps/helpers";
import { haversineDistance } from "../maps/helpers";

function pointToLineDistance(point, lineStart, lineEnd) {
  const x = point.lat;
  const y = point.lng;
  const x1 = lineStart.lat;
  const y1 = lineStart.lng;
  const x2 = lineEnd.lat;
  const y2 = lineEnd.lng;

  const A = x - x1;
  const B = y - y1;
  const C = x2 - x1;
  const D = y2 - y1;

  const dot = A * C + B * D;
  const lenSq = C * C + D * D;
  let param = -1;

  if (lenSq !== 0) {
    param = dot / lenSq;
  }

  let xx, yy;

  if (param < 0) {
    xx = x1;
    yy = y1;
  } else if (param > 1) {
    xx = x2;
    yy = y2;
  } else {
    xx = x1 + param * C;
    yy = y1 + param * D;
  }

  const dx = x - xx;
  const dy = y - yy;

  return Math.sqrt(dx * dx + dy * dy);
}

export function calculateSpeed(point1, point2) {
  if (!point1 || !point2 || !point1[4] || !point2[4]) {
    console.warn('Invalid points for speed calculation:', { point1, point2 });
    return 0;
  }

  const distanceKm = haversineDistance(point1[0], point1[1], point2[0], point2[1]); // in kilometers
  const timeDiffSeconds = point2[4] - point1[4];

  // Handle edge cases
  if (timeDiffSeconds <= 0 || distanceKm <= 0) {
    return 0;
  }

  const speedKmh = (distanceKm / timeDiffSeconds) * 3600; // Convert to km/h

  // Cap speed at reasonable maximum (e.g., 150 km/h)
  const MAX_SPEED = 150;
  return Math.min(speedKmh, MAX_SPEED);
}

// Optimize getSpeedColor by pre-calculating color stops
const colorStops = [
  { speed: 0, color: '#00ff00' },    // Stationary/very slow (green)
  { speed: 15, color: '#00ffff' },   // Walking/jogging (cyan)
  { speed: 30, color: '#ff00ff' },   // Cycling/slow driving (magenta)
  { speed: 50, color: '#ffff00' },   // Urban driving (yellow)
  { speed: 100, color: '#ff3300' }   // Highway driving (red)
].map(stop => ({
  ...stop,
  rgb: hexToRGB(stop.color)
}));

export function getSpeedColor(speedKmh, useSpeedColors) {
  if (!useSpeedColors) {
    return '#0000ff';
  }

  // Find the appropriate color segment
  for (let i = 1; i < colorStops.length; i++) {
    if (speedKmh <= colorStops[i].speed) {
      const ratio = (speedKmh - colorStops[i-1].speed) / (colorStops[i].speed - colorStops[i-1].speed);
      const color1 = colorStops[i-1].rgb;
      const color2 = colorStops[i].rgb;

      const r = Math.round(color1.r + (color2.r - color1.r) * ratio);
      const g = Math.round(color1.g + (color2.g - color1.g) * ratio);
      const b = Math.round(color1.b + (color2.b - color1.b) * ratio);

      return `rgb(${r}, ${g}, ${b})`;
    }
  }

  return colorStops[colorStops.length - 1].color;
}

// Helper function to convert hex to RGB
function hexToRGB(hex) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return { r, g, b };
}

// Add new function for batch processing
function processInBatches(items, batchSize, processFn) {
  let index = 0;
  const totalItems = items.length;

  function processNextBatch() {
    const batchStartTime = performance.now();
    let processedInThisFrame = 0;

    // Process as many items as possible within our time budget
    while (index < totalItems && processedInThisFrame < 500) {
      const end = Math.min(index + batchSize, totalItems);

      // Ensure we're within bounds
      for (let i = index; i < end; i++) {
        if (items[i]) {  // Add null check
          processFn(items[i]);
        }
      }

      processedInThisFrame += (end - index);
      index = end;

      if (performance.now() - batchStartTime > 32) {
        break;
      }
    }

    if (index < totalItems) {
      setTimeout(processNextBatch, 0);
    } else {
      // Only clear the array after all processing is complete
      items.length = 0;
    }
  }

  processNextBatch();
}

export function addHighlightOnHover(polylineGroup, map, polylineCoordinates, userSettings, distanceUnit) {
  const startPoint = polylineCoordinates[0];
  const endPoint = polylineCoordinates[polylineCoordinates.length - 1];

  const firstTimestamp = formatDate(startPoint[4], userSettings.timezone);
  const lastTimestamp = formatDate(endPoint[4], userSettings.timezone);

  const minutes = Math.round((endPoint[4] - startPoint[4]) / 60);
  const timeOnRoute = minutesToDaysHoursMinutes(minutes);

  const totalDistance = polylineCoordinates.reduce((acc, curr, index, arr) => {
    if (index === 0) return acc;
    const dist = haversineDistance(arr[index - 1][0], arr[index - 1][1], curr[0], curr[1]);
    return acc + dist;
  }, 0);

  const startIcon = L.divIcon({ html: "🚥", className: "emoji-icon" });
  const finishIcon = L.divIcon({ html: "🏁", className: "emoji-icon" });

  const startMarker = L.marker([startPoint[0], startPoint[1]], { icon: startIcon });
  const endMarker = L.marker([endPoint[0], endPoint[1]], { icon: finishIcon });

  let hoverPopup = null;

  // Add events to both group and individual polylines
  polylineGroup.eachLayer((layer) => {
    if (layer instanceof L.Polyline) {
      layer.on("mouseover", function (e) {
        console.log("Individual polyline mouseover", e);
        handleMouseOver(e);
      });

      layer.on("mouseout", function (e) {
        console.log("Individual polyline mouseout", e);
        handleMouseOut(e);
      });
    }
  });

  function handleMouseOver(e) {
    console.log('Individual polyline mouseover', e);

    // Handle both direct layer events and group propagated events
    const layer = e.layer || e.target;
    let speed = 0;

    if (layer instanceof L.Polyline) {
      // Get the coordinates array from the layer
      const coords = layer.getLatLngs();
      if (coords && coords.length >= 2) {
        const startPoint = coords[0];
        const endPoint = coords[coords.length - 1];

        // Find the corresponding markers for these coordinates
        const startMarkerData = polylineCoordinates.find(m =>
          m[0] === startPoint.lat && m[1] === startPoint.lng
        );
        const endMarkerData = polylineCoordinates.find(m =>
          m[0] === endPoint.lat && m[1] === endPoint.lng
        );

        // Calculate speed if we have both markers
        if (startMarkerData && endMarkerData) {
          speed = startMarkerData[5] || endMarkerData[5] || 0;
        }
      }
    }

    // Apply style to all segments in the group
    polylineGroup.eachLayer((segment) => {
      if (segment instanceof L.Polyline) {
        const newStyle = {
          weight: 8,
          opacity: 0.8
        };

        // Only change color if speed-colored routes are not enabled
        console.log("speed_colored_routes", userSettings.speed_colored_routes);
        if (!userSettings.speed_colored_routes) {
          newStyle.color = "yellow"
        }

        segment.setStyle(newStyle);
      }
    });

    startMarker.addTo(map);
    endMarker.addTo(map);

    const popupContent = `
      <strong>Start:</strong> ${firstTimestamp}<br>
      <strong>End:</strong> ${lastTimestamp}<br>
      <strong>Duration:</strong> ${timeOnRoute}<br>
      <strong>Total Distance:</strong> ${formatDistance(totalDistance, distanceUnit)}<br>
      <strong>Current Speed:</strong> ${Math.round(speed)} km/h
    `;

    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }

    hoverPopup = L.popup()
      .setLatLng(e.latlng)
      .setContent(popupContent)
      .openOn(map);
  }

  function handleMouseOut(e) {
    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        const originalStyle = {
          weight: 3,
          opacity: userSettings.route_opacity,
          color: layer.options.originalColor
        };

        layer.setStyle(originalStyle);
      }
    });

    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }
    map.removeLayer(startMarker);
    map.removeLayer(endMarker);
  }

  // Keep the original group events as a fallback
  polylineGroup.on("mouseover", handleMouseOver);
  polylineGroup.on("mouseout", handleMouseOut);

  // Keep the click event
  polylineGroup.on("click", function () {
    map.fitBounds(polylineGroup.getBounds());
  });
}

export function createPolylinesLayer(markers, map, timezone, routeOpacity, userSettings, distanceUnit) {
  // Create a custom pane for our polylines with higher z-index
  if (!map.getPane('polylinesPane')) {
    map.createPane('polylinesPane');
    map.getPane('polylinesPane').style.zIndex = 450; // Above the default overlay pane (400)
  }

  const renderer = L.canvas({
    padding: 0.5,
    pane: 'polylinesPane'
  });

  console.log("Creating polylines layer with markers:", markers.length);

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
      const distance = haversineDistance(lastPoint[0], lastPoint[1], currentPoint[0], currentPoint[1]);
      const timeDifference = (currentPoint[4] - lastPoint[4]) / 60;

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

  console.log("Split into polyline groups:", splitPolylines.length);

  // Create the layer group with the polylines
  const layerGroup = L.layerGroup(
    splitPolylines.map((polylineCoordinates, groupIndex) => {
      console.log(`Creating group ${groupIndex} with coordinates:`, polylineCoordinates.length);

      const segmentGroup = L.featureGroup();
      const segments = [];

      for (let i = 0; i < polylineCoordinates.length - 1; i++) {
        const speed = calculateSpeed(polylineCoordinates[i], polylineCoordinates[i + 1]);
        const color = getSpeedColor(speed, userSettings.speed_colored_routes);

        const segment = L.polyline(
          [
            [polylineCoordinates[i][0], polylineCoordinates[i][1]],
            [polylineCoordinates[i + 1][0], polylineCoordinates[i + 1][1]]
          ],
          {
            renderer: renderer,
            color: color,
            originalColor: color,
            opacity: routeOpacity,
            weight: 3,
            speed: speed,
            interactive: true,
            pane: 'polylinesPane',
            bubblingMouseEvents: false
          }
        );

        segments.push(segment);
        segmentGroup.addLayer(segment);
      }

      // Add mouseover/mouseout to the entire group
      segmentGroup.on('mouseover', function(e) {
        console.log("Group mouseover", groupIndex);
        L.DomEvent.stopPropagation(e);
        segments.forEach(segment => {
          segment.setStyle({
            weight: 8,
            opacity: 1
          });
          if (map.hasLayer(segment)) {
            segment.bringToFront();
          }
        });
      });

      segmentGroup.on('mouseout', function(e) {
        console.log("Group mouseout", groupIndex);
        L.DomEvent.stopPropagation(e);
        segments.forEach(segment => {
          segment.setStyle({
            weight: 3,
            opacity: routeOpacity,
            color: segment.options.originalColor
          });
        });
      });

      // Make the group interactive
      segmentGroup.options.interactive = true;
      segmentGroup.options.bubblingMouseEvents = false;

      // Add the hover functionality to the group
      addHighlightOnHover(segmentGroup, map, polylineCoordinates, userSettings, distanceUnit);

      return segmentGroup;
    })
  );

  // Add CSS to ensure our pane receives mouse events
  const style = document.createElement('style');
  style.textContent = `
    .leaflet-polylinesPane-pane {
      pointer-events: auto !important;
    }
    .leaflet-polylinesPane-pane canvas {
      pointer-events: auto !important;
    }
  `;
  document.head.appendChild(style);

  // Add to map and return
  layerGroup.addTo(map);
  console.log("Layer group added to map");

  return layerGroup;
}

export function updatePolylinesColors(polylinesLayer, useSpeedColors) {
  const defaultStyle = {
    color: '#0000ff',
    originalColor: '#0000ff'
  };

  // More efficient segment collection
  const segments = new Array();
  polylinesLayer.eachLayer(groupLayer => {
    if (groupLayer instanceof L.LayerGroup) {
      groupLayer.eachLayer(segment => {
        if (segment instanceof L.Polyline) {
          segments.push(segment);
        }
      });
    }
  });

  // Reuse style object to reduce garbage collection
  const styleObj = {};

  // Process segments in larger batches
  processInBatches(segments, 200, (segment) => {
    try {
      if (!useSpeedColors) {
        segment.setStyle(defaultStyle);
        return;
      }

      const speed = segment.options.speed || 0;
      const newColor = getSpeedColor(speed, true);

      // Reuse style object
      styleObj.color = newColor;
      styleObj.originalColor = newColor;
      segment.setStyle(styleObj);
    } catch (error) {
      console.error('Error processing segment:', error);
    }
  });
}

export function updatePolylinesOpacity(polylinesLayer, opacity) {
  const segments = [];

  // Collect all segments first
  polylinesLayer.eachLayer((groupLayer) => {
    if (groupLayer instanceof L.LayerGroup) {
      groupLayer.eachLayer((segment) => {
        if (segment instanceof L.Polyline) {
          segments.push(segment);
        }
      });
    }
  });

  // Process segments in batches of 50
  processInBatches(segments, 50, (segment) => {
    segment.setStyle({ opacity: opacity });
  });
}
