import { createInteractiveMarker, createSimplifiedMarker } from "./marker_factory";
import { haversineDistance } from "./helpers";

export function createMarkersArray(markersData, userSettings, apiKey) {
  // Create a canvas renderer
  const renderer = L.canvas({ padding: 0.5 });

  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData, renderer, userSettings);
  } else {
    return markersData.map((marker, index) => {
      return createInteractiveMarker(marker, index, userSettings, apiKey, renderer);
    });
  }
}


export function createSimplifiedMarkers(markersData, renderer, userSettings) {
  const distanceThreshold = 50; // meters
  const timeThreshold = 20000; // milliseconds (3 seconds)

  const simplifiedMarkers = [];
  let previousMarker = markersData[0]; // Start with the first marker
  simplifiedMarkers.push(previousMarker); // Always keep the first marker

  markersData.forEach((currentMarker, index) => {
    if (index === 0) return; // Skip the first marker

    const [currLat, currLon, , , currTimestamp] = currentMarker;
    const [prevLat, prevLon, , , prevTimestamp] = previousMarker;

    const timeDiff = currTimestamp - prevTimestamp;
    // Use haversineDistance for accurate distance calculation
    const distance = haversineDistance(prevLat, prevLon, currLat, currLon, 'km') * 1000; // Convert to meters

    // Keep the marker if it's far enough in distance or time
    if (distance >= distanceThreshold || timeDiff >= timeThreshold) {
      simplifiedMarkers.push(currentMarker);
      previousMarker = currentMarker;
    }
  });

  // Now create markers for the simplified data using the factory
  return simplifiedMarkers.map((marker) => {
    return createSimplifiedMarker(marker, userSettings);
  });
}
