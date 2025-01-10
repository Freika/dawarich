import { formatDate } from "../maps/helpers";
import { formatDistance } from "../maps/helpers";
import { getUrlParameter } from "../maps/helpers";
import { minutesToDaysHoursMinutes } from "../maps/helpers";
import { haversineDistance } from "../maps/helpers";

function getSpeedColor(speedKmh) {
  console.log('Speed to color:', speedKmh + ' km/h');

  if (speedKmh > 100) {
    console.log('Red - Very fast');
    return '#FF0000';
  }
  if (speedKmh > 70) {
    console.log('Orange - Fast');
    return '#FFA500';
  }
  if (speedKmh > 40) {
    console.log('Yellow - Moderate');
    return '#FFFF00';
  }
  if (speedKmh > 20) {
    console.log('Light green - Normal');
    return '#90EE90';
  }
  console.log('Green - Slow');
  return '#008000';
}

function calculateSpeed(point1, point2) {
  const distanceKm = haversineDistance(point1[0], point1[1], point2[0], point2[1]); // in kilometers
  const timeDiffSeconds = point2[4] - point1[4];

  // Convert to km/h: (kilometers / seconds) * (3600 seconds / hour)
  const speed = (distanceKm / timeDiffSeconds) * 3600;

  console.log('Speed calculation:', {
    distance: distanceKm + ' km',
    timeDiff: timeDiffSeconds + ' seconds',
    speed: speed + ' km/h',
    point1: point1,
    point2: point2
  });

  return speed;
}

export function addHighlightOnHover(polylineGroup, map, polylineCoordinates, userSettings, distanceUnit) {
  const highlightStyle = { opacity: 1, weight: 5 };
  const normalStyle = { opacity: userSettings.routeOpacity, weight: 3 };

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
    // Find the closest segment and its speed
    let closestSegment = null;
    let minDistance = Infinity;
    let currentSpeed = 0;

    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        const layerLatLngs = layer.getLatLngs();
        const distance = L.LineUtil.pointToSegmentDistance(
          e.latlng,
          layerLatLngs[0],
          layerLatLngs[1]
        );

        if (distance < minDistance) {
          minDistance = distance;
          closestSegment = layer;

          // Get the coordinates of the segment
          const startPoint = layerLatLngs[0];
          const endPoint = layerLatLngs[1];

          console.log('Closest segment found:', {
            startPoint,
            endPoint,
            distance
          });

          // Find matching points in polylineCoordinates
          const startIdx = polylineCoordinates.findIndex(p => {
            const latMatch = Math.abs(p[0] - startPoint.lat) < 0.0000001;
            const lngMatch = Math.abs(p[1] - startPoint.lng) < 0.0000001;
            return latMatch && lngMatch;
          });

          console.log('Start point index:', startIdx);
          console.log('Original point:', startIdx !== -1 ? polylineCoordinates[startIdx] : 'not found');

          if (startIdx !== -1 && startIdx < polylineCoordinates.length - 1) {
            currentSpeed = calculateSpeed(
              polylineCoordinates[startIdx],
              polylineCoordinates[startIdx + 1]
            );
            console.log('Speed calculated:', currentSpeed);
          }
        }
      }
    });

    // Highlight all segments in the group
    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({
          ...highlightStyle,
          color: layer.options.originalColor
        });
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
    // Restore original styles for all segments
    polylineGroup.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({
          ...normalStyle,
          color: layer.options.originalColor
        });
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

  // Split into separate polylines based on distance/time thresholds
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

      // Create segments with different colors based on speed
      for (let i = 0; i < polylineCoordinates.length - 1; i++) {
        const speed = calculateSpeed(polylineCoordinates[i], polylineCoordinates[i + 1]);
        const color = getSpeedColor(speed);

        const segment = L.polyline(
          [
            [polylineCoordinates[i][0], polylineCoordinates[i][1]],
            [polylineCoordinates[i + 1][0], polylineCoordinates[i + 1][1]]
          ],
          {
            color: color,
            originalColor: color,
            opacity: routeOpacity,
            weight: 3
          }
        );

        segmentGroup.addLayer(segment);
      }

      // Add hover effect to the entire group of segments
      addHighlightOnHover(segmentGroup, map, polylineCoordinates, userSettings, distanceUnit);

      return segmentGroup;
    })
  ).addTo(map);
}

export function updatePolylinesOpacity(polylinesLayer, opacity) {
  polylinesLayer.eachLayer((groupLayer) => {
    if (groupLayer instanceof L.LayerGroup) {
      groupLayer.eachLayer((segment) => {
        if (segment instanceof L.Polyline) {
          segment.setStyle({ opacity: opacity });
        }
      });
    }
  });
}
