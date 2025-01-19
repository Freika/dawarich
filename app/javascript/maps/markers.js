import { createPopupContent } from "./popups";

export function createMarkersArray(markersData, userSettings) {
  // Create a canvas renderer
  const renderer = L.canvas({ padding: 0.5 });

  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData, renderer);
  } else {
    return markersData.map((marker) => {
      const [lat, lon] = marker;
      const popupContent = createPopupContent(marker, userSettings.timezone, userSettings.distanceUnit);
      let markerColor = marker[5] < 0 ? "orange" : "blue";

      // Use L.marker instead of L.circleMarker for better drag support
      return L.marker([lat, lon], {
        icon: L.divIcon({
          className: 'custom-div-icon',
          html: `<div style='background-color: ${markerColor}; width: 8px; height: 8px; border-radius: 50%;'></div>`,
          iconSize: [8, 8],
          iconAnchor: [4, 4]
        }),
        draggable: true,
        autoPan: true
      }).bindPopup(popupContent, { autoClose: false })
        .on('dragstart', function(e) {
          this.closePopup();
        })
        .on('dragend', function(e) {
          const newLatLng = e.target.getLatLng();
          this.setLatLng(newLatLng);
          this.openPopup();
        });
    });
  }
}

export function createSimplifiedMarkers(markersData, renderer) {
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

    // Use L.marker instead of L.circleMarker for better drag support
    return L.marker([lat, lon], {
      icon: L.divIcon({
        className: 'custom-div-icon',
        html: `<div style='background-color: ${markerColor}; width: 8px; height: 8px; border-radius: 50%;'></div>`,
        iconSize: [8, 8],
        iconAnchor: [4, 4]
      }),
      draggable: true,
      autoPan: true
    }).bindPopup(popupContent)
      .on('dragstart', function(e) {
        this.closePopup();
      })
      .on('dragend', function(e) {
        const newLatLng = e.target.getLatLng();
        this.setLatLng(newLatLng);
        this.openPopup();
      });
  });
}
