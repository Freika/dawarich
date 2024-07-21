// Markers, polylines, and popups

export function createPolylinesLayer(markers, map, timezone) {
  const splitPolylines = [];
  let currentPolyline = [];
  const distanceThresholdMeters = parseInt(this.element.dataset.meters_between_routes) || 500;
  const timeThresholdMinutes = parseInt(this.element.dataset.minutes_between_routes) || 60;

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
    splitPolylines.map((polylineCoordinates, index) => {
      const latLngs = polylineCoordinates.map((point) => [point[0], point[1]]);
      const polyline = L.polyline(latLngs, { color: "blue", opacity: 0.6, weight: 3 });

      const startPoint = polylineCoordinates[0];
      const endPoint = polylineCoordinates[polylineCoordinates.length - 1];
      const prevPoint = index > 0 ? splitPolylines[index - 1][splitPolylines[index - 1].length - 1] : null;
      const nextPoint = index < splitPolylines.length - 1 ? splitPolylines[index + 1][0] : null;

      this.addHighlightOnHover(polyline, map, startPoint, endPoint, prevPoint, nextPoint, timezone);

      return polyline;
    })
  ).addTo(map);
}
