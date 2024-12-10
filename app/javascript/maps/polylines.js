import { formatDistance } from "../maps/helpers";
import { getUrlParameter } from "../maps/helpers";
import { minutesToDaysHoursMinutes } from "../maps/helpers";
import { haversineDistance } from "../maps/helpers";

export function addHighlightOnHover(polyline, map, polylineCoordinates, userSettings, distanceUnit) {
  const originalStyle = { color: "blue", opacity: userSettings.routeOpacity, weight: 3 };
  const highlightStyle = { color: "yellow", opacity: 1, weight: 5 };

  polyline.setStyle(originalStyle);

  const startPoint = polylineCoordinates[0];
  const endPoint = polylineCoordinates[polylineCoordinates.length - 1];

  const firstTimestamp = new Date(startPoint[4] * 1000).toLocaleString("en-GB", { timeZone: userSettings.timezone });
  const lastTimestamp = new Date(endPoint[4] * 1000).toLocaleString("en-GB", { timeZone: userSettings.timezone });

  const minutes = Math.round((endPoint[4] - startPoint[4]) / 60);
  const timeOnRoute = minutesToDaysHoursMinutes(minutes);

  const totalDistance = polylineCoordinates.reduce((acc, curr, index, arr) => {
    if (index === 0) return acc;
    const dist = haversineDistance(arr[index - 1][0], arr[index - 1][1], curr[0], curr[1]);
    return acc + dist;
  }, 0);

  const startIcon = L.divIcon({ html: "🚥", className: "emoji-icon" });
  const finishIcon = L.divIcon({ html: "🏁", className: "emoji-icon" });

  const isDebugMode = getUrlParameter("debug") === "true";

  let popupContent = `
    <strong>Start:</strong> ${firstTimestamp}<br>
    <strong>End:</strong> ${lastTimestamp}<br>
    <strong>Duration:</strong> ${timeOnRoute}<br>
    <strong>Total Distance:</strong> ${formatDistance(totalDistance, distanceUnit)}<br>
  `;

  if (isDebugMode) {
    const prevPoint = polylineCoordinates[0];
    const nextPoint = polylineCoordinates[polylineCoordinates.length - 1];
    const distanceToPrev = haversineDistance(prevPoint[0], prevPoint[1], startPoint[0], startPoint[1]);
    const distanceToNext = haversineDistance(endPoint[0], endPoint[1], nextPoint[0], nextPoint[1]);

    const timeBetweenPrev = Math.round((startPoint[4] - prevPoint[4]) / 60);
    const timeBetweenNext = Math.round((endPoint[4] - nextPoint[4]) / 60);
    const pointsNumber = polylineCoordinates.length;

    popupContent += `
      <strong>Prev Route:</strong> ${Math.round(distanceToPrev)}m and ${minutesToDaysHoursMinutes(timeBetweenPrev)} away<br>
      <strong>Next Route:</strong> ${Math.round(distanceToNext)}m and ${minutesToDaysHoursMinutes(timeBetweenNext)} away<br>
      <strong>Points:</strong> ${pointsNumber}<br>
    `;
  }

  const startMarker = L.marker([startPoint[0], startPoint[1]], { icon: startIcon }).bindPopup(`Start: ${firstTimestamp}`);
  const endMarker = L.marker([endPoint[0], endPoint[1]], { icon: finishIcon }).bindPopup(popupContent);

  let hoverPopup = null;

  polyline.on("mouseover", function (e) {
    polyline.setStyle(highlightStyle);
    startMarker.addTo(map);
    endMarker.addTo(map);

    const latLng = e.latlng;
    if (hoverPopup) {
      map.closePopup(hoverPopup);
    }
    hoverPopup = L.popup()
      .setLatLng(latLng)
      .setContent(popupContent)
      .openOn(map);
  });

  polyline.on("mouseout", function () {
    polyline.setStyle(originalStyle);
    map.closePopup(hoverPopup);
    map.removeLayer(startMarker);
    map.removeLayer(endMarker);
  });

  polyline.on("click", function () {
    map.fitBounds(polyline.getBounds());
  });

  // Close the popup when clicking elsewhere on the map
  map.on("click", function () {
    map.closePopup(hoverPopup);
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
      const latLngs = polylineCoordinates.map((point) => [point[0], point[1]]);
      const polyline = L.polyline(latLngs, { color: "blue", opacity: 0.6, weight: 3 });

      addHighlightOnHover(polyline, map, polylineCoordinates, userSettings, distanceUnit);

      return polyline;
    })
  ).addTo(map);
}

export function updatePolylinesOpacity(polylinesLayer, opacity) {
  polylinesLayer.eachLayer((layer) => {
    if (layer instanceof L.Polyline) {
      layer.setStyle({ opacity: opacity });
    }
  });
}
