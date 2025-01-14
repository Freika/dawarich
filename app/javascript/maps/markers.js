import { createPopupContent } from "./popups";

export function createMarkersArray(markersData, userSettings, apiKey) {
  if (!markersData || !markersData.length) {
    console.warn('No marker data provided');
    return { markers: [], polyline: null };
  }

  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData);
  } else {
    try {
      // Create an array to store all coordinates for the polyline
      const coordinates = markersData.map(marker => {
        if (!Array.isArray(marker) || marker.length < 2) {
          console.warn('Invalid marker data:', marker);
          return null;
        }
        return [marker[0], marker[1]];
      }).filter(coord => coord !== null);

      // Create the polyline
      const polyline = L.polyline(coordinates, {
        color: 'blue',
        weight: 2
      });

      const markers = markersData.map((marker, index) => {
        if (!Array.isArray(marker) || marker.length < 2) {
          console.warn('Invalid marker data:', marker);
          return null;
        }

        const [lat, lon] = marker;
        const pointId = marker[6]; // Assuming the ID is at index 6

        if (typeof lat !== 'number' || typeof lon !== 'number') {
          console.warn('Invalid coordinates:', lat, lon);
          return null;
        }

        const popupContent = createPopupContent(marker, userSettings.timezone, userSettings.distanceUnit);
        let markerColor = marker[5] < 0 ? "orange" : "blue";

        const icon = L.divIcon({
          className: 'custom-div-icon',
          html: `<div style="background-color: ${markerColor}; width: 8px; height: 8px; border-radius: 50%;"></div>`,
          iconSize: [8, 8]
        });

        return L.marker([lat, lon], {
          icon: icon,
          draggable: true,
          zIndexOffset: 1000,
          markerIndex: index
        }).bindPopup(popupContent, { autoClose: false })
          .on('dragend', function(event) {
            const marker = event.target;
            const position = marker.getLatLng();
            const index = marker.options.markerIndex;

            // Update the polyline coordinates
            const latlngs = polyline.getLatLngs();
            latlngs[index] = position;
            polyline.setLatLngs(latlngs);

            // Send API request to update point position
            fetch(`/api/v1/points/${pointId}?api_key=${apiKey}`, {
              method: 'PATCH',
              headers: {
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                point: {
                  latitude: position.lat,
                  longitude: position.lng
                }
              })
            })
            .then(response => {
              if (!response.ok) {
                throw new Error('Failed to update point position');
              }
              return response.json();
            })
            .then(data => {
              // Show success message
              if (window.showFlashMessage) {
                window.showFlashMessage('notice', 'Point position updated successfully');
              }
            })
            .catch(error => {
              console.error('Error updating point position:', error);
              // Show error message
              if (window.showFlashMessage) {
                window.showFlashMessage('error', 'Failed to update point position');
              }
              // Revert the marker position
              marker.setLatLng([lat, lon]);
              latlngs[index] = [lat, lon];
              polyline.setLatLngs(latlngs);
            });
          });
      }).filter(marker => marker !== null);

      return [...markers, polyline];
    } catch (error) {
      console.error('Error creating markers:', error);
      return [];
    }
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
