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
  { speed: 50, color: '#ff3300' },   // Urban driving (orange-red)
  { speed: 100, color: '#ffff00' }   // Highway driving (yellow)
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

  polylineGroup.on("mouseover", function (e) {
    let closestSegment = null;
    let minDistance = Infinity;
    let currentSpeed = 0;

    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        const layerLatLngs = layer.getLatLngs();
        const distance = pointToLineDistance(e.latlng, layerLatLngs[0], layerLatLngs[1]);

        if (distance < minDistance) {
          minDistance = distance;
          closestSegment = layer;

          const startIdx = polylineCoordinates.findIndex(p => {
            const latMatch = Math.abs(p[0] - layerLatLngs[0].lat) < 0.0000001;
            const lngMatch = Math.abs(p[1] - layerLatLngs[0].lng) < 0.0000001;
            return latMatch && lngMatch;
          });

          if (startIdx !== -1 && startIdx < polylineCoordinates.length - 1) {
            currentSpeed = calculateSpeed(
              polylineCoordinates[startIdx],
              polylineCoordinates[startIdx + 1]
            );
          }
        }
      }
    });

    // Apply highlight style to all segments
    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        const highlightStyle = {
          weight: 5,
          opacity: 1
        };

        // Only change color to yellow if speed colors are disabled
        if (!userSettings.speed_colored_polylines) {
          highlightStyle.color = '#ffff00';
        }

        layer.setStyle(highlightStyle);
      }
    });

    startMarker.addTo(map);
    endMarker.addTo(map);

    const popupContent = `
      <strong>Start:</strong> ${firstTimestamp}<br>
      <strong>End:</strong> ${lastTimestamp}<br>
      <strong>Duration:</strong> ${timeOnRoute}<br>
      <strong>Total Distance:</strong> ${formatDistance(totalDistance, distanceUnit)}<br>
      <strong>Current Speed:</strong> ${Math.round(currentSpeed)} km/h
    `;

    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }

    hoverPopup = L.popup()
      .setLatLng(e.latlng)
      .setContent(popupContent)
      .openOn(map);
  });

  polylineGroup.on("mouseout", function () {
    // Restore original style
    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        const originalStyle = {
          weight: 3,
          opacity: userSettings.route_opacity,
          color: layer.options.originalColor // Use the stored original color
        };

        layer.setStyle(originalStyle);
      }
    });

    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }
    map.removeLayer(startMarker);
    map.removeLayer(endMarker);
  });

  polylineGroup.on("click", function () {
    map.fitBounds(polylineGroup.getBounds());
  });
}

export function createPolylinesLayer(markers, map, timezone, routeOpacity, userSettings, distanceUnit) {
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

  return L.layerGroup(
    splitPolylines.map((polylineCoordinates) => {
      const segmentGroup = L.featureGroup();

      for (let i = 0; i < polylineCoordinates.length - 1; i++) {
        const speed = calculateSpeed(polylineCoordinates[i], polylineCoordinates[i + 1]);

        const color = getSpeedColor(speed, userSettings.speed_colored_polylines);

        const segment = L.polyline(
          [
            [polylineCoordinates[i][0], polylineCoordinates[i][1]],
            [polylineCoordinates[i + 1][0], polylineCoordinates[i + 1][1]]
          ],
          {
            color: color,
            originalColor: color,
            opacity: routeOpacity,
            weight: 3,
            speed: speed,  // Store the calculated speed
            startTime: polylineCoordinates[i][4],
            endTime: polylineCoordinates[i + 1][4]
          }
        );

        segmentGroup.addLayer(segment);
      }

      addHighlightOnHover(segmentGroup, map, polylineCoordinates, userSettings, distanceUnit);

      return segmentGroup;
    })
  ).addTo(map);
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
