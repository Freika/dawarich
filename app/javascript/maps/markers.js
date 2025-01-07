import { createPopupContent } from "./popups";

export function createMarkersArray(markersData, userSettings) {
  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData);
  } else {
    return markersData.map((marker) => {
      const [lat, lon] = marker;

      const popupContent = createPopupContent(marker, userSettings.timezone, userSettings.distanceUnit);
      let markerColor = marker[5] < 0 ? "orange" : "blue";
      return L.circleMarker([lat, lon], {
        radius: 4,
        color: markerColor,
        zIndexOffset: 1000,
        pane: 'markerPane'
      }).bindPopup(popupContent, { autoClose: false });
    });
  }
}

export function createSimplifiedMarkers(markersData) {
  const distanceThreshold = 50; // meters
  const timeThreshold = 20000; // milliseconds (3 seconds)

  const simplifiedMarkers = [];
  let previousMarker = markersData[0]; // Start with the first marker
  simplifiedMarkers.push(previousMarker); // Always keep the first marker

  markersData.forEach((currentMarker, index) => {
    if (index === 0) return; // Skip the first marker

    const [prevLat, prevLon, prevTimestamp] = previousMarker;
    const [currLat, currLon, currTimestamp] = currentMarker;

    const timeDiff = currTimestamp - prevTimestamp;
    const distance = haversineDistance(prevLat, prevLon, currLat, currLon, 'km') * 1000; // Convert km to meters

    // Keep the marker if it's far enough in distance or time
    if (distance >= distanceThreshold || timeDiff >= timeThreshold) {
      simplifiedMarkers.push(currentMarker);
      previousMarker = currentMarker;
    }
  });

  // Now create markers for the simplified data
  return simplifiedMarkers.map((marker) => {
    const [lat, lon] = marker;
    const popupContent = createPopupContent(marker);
    let markerColor = marker[5] < 0 ? "orange" : "blue";
    return L.circleMarker(
      [lat, lon],
      { radius: 4, color: markerColor, zIndexOffset: 1000 }
    ).bindPopup(popupContent);
  });
}
