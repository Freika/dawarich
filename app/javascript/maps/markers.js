import { createPopupContent } from "./popups";

export function createMarkersArray(markersData, userSettings, apiKey) {
  // Create a canvas renderer
  const renderer = L.canvas({ padding: 0.5 });

  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData, renderer);
  } else {
    return markersData.map((marker, index) => {
      const [lat, lon] = marker;
      const pointId = marker[6];  // ID is at index 6
      const markerColor = marker[5] < 0 ? "orange" : "blue";

      return L.marker([lat, lon], {
        icon: L.divIcon({
          className: 'custom-div-icon',
          html: `<div style='background-color: ${markerColor}; width: 8px; height: 8px; border-radius: 50%;'></div>`,
          iconSize: [8, 8],
          iconAnchor: [4, 4]
        }),
        draggable: true,
        autoPan: true,
        pointIndex: index,
        pointId: pointId,
        originalLat: lat,
        originalLng: lon,
        markerData: marker,  // Store the complete marker data
        renderer: renderer
      }).bindPopup(createPopupContent(marker, userSettings.timezone, userSettings.distanceUnit))
        .on('dragstart', function(e) {
          this.closePopup();
        })
        .on('drag', function(e) {
          const newLatLng = e.target.getLatLng();
          const map = e.target._map;
          const pointIndex = e.target.options.pointIndex;
          const originalLat = e.target.options.originalLat;
          const originalLng = e.target.options.originalLng;
          // Find polylines by iterating through all map layers
          map.eachLayer((layer) => {
            // Check if this is a LayerGroup containing polylines
            if (layer instanceof L.LayerGroup) {
              layer.eachLayer((featureGroup) => {
                if (featureGroup instanceof L.FeatureGroup) {
                  featureGroup.eachLayer((segment) => {
                    if (segment instanceof L.Polyline) {
                      const coords = segment.getLatLngs();
                      const tolerance = 0.0000001;
                      let updated = false;

                      // Check and update start point
                      if (Math.abs(coords[0].lat - originalLat) < tolerance &&
                          Math.abs(coords[0].lng - originalLng) < tolerance) {
                        coords[0] = newLatLng;
                        updated = true;
                      }

                      // Check and update end point
                      if (Math.abs(coords[1].lat - originalLat) < tolerance &&
                          Math.abs(coords[1].lng - originalLng) < tolerance) {
                        coords[1] = newLatLng;
                        updated = true;
                      }

                      // Only update if we found a matching endpoint
                      if (updated) {
                        segment.setLatLngs(coords);
                        segment.redraw();
                      }
                    }
                  });
                }
              });
            }
          });

          // Update the marker's original position for the next drag event
          e.target.options.originalLat = newLatLng.lat;
          e.target.options.originalLng = newLatLng.lng;
        })
        .on('dragend', function(e) {
          const newLatLng = e.target.getLatLng();
          const pointId = e.target.options.pointId;
          const pointIndex = e.target.options.pointIndex;
          const originalMarkerData = e.target.options.markerData;

          fetch(`/api/v1/points/${pointId}`, {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': `Bearer ${apiKey}`
            },
            body: JSON.stringify({
              point: {
                latitude: newLatLng.lat.toString(),
                longitude: newLatLng.lng.toString()
              }
            })
          })
          .then(response => {
            if (!response.ok) {
              throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.json();
          })
          .then(data => {
            const map = e.target._map;
            if (map && map.mapsController && map.mapsController.markers) {
              const markers = map.mapsController.markers;
              if (markers[pointIndex]) {
                markers[pointIndex][0] = parseFloat(data.latitude);
                markers[pointIndex][1] = parseFloat(data.longitude);
              }
            }

            // Create updated marker data array
            const updatedMarkerData = [
              parseFloat(data.latitude),
              parseFloat(data.longitude),
              originalMarkerData[2],  // battery
              originalMarkerData[3],  // altitude
              originalMarkerData[4],  // timestamp
              originalMarkerData[5],  // velocity
              data.id,                // id
              originalMarkerData[7]   // country
            ];

            // Update the marker's stored data
            e.target.options.markerData = updatedMarkerData;

            // Update the popup content
            if (this._popup) {
              const updatedPopupContent = createPopupContent(
                updatedMarkerData,
                userSettings.timezone,
                userSettings.distanceUnit
              );
              this.setPopupContent(updatedPopupContent);
            }
          })
          .catch(error => {
            console.error('Error updating point:', error);
            this.setLatLng([e.target.options.originalLat, e.target.options.originalLng]);
            alert('Failed to update point position. Please try again.');
          });
        });
    });
  }
}

// Helper function to check if a point is connected to a polyline endpoint
function isConnectedToPoint(latLng, originalPoint, tolerance) {
  // originalPoint is [lat, lng] array
  const latMatch = Math.abs(latLng.lat - originalPoint[0]) < tolerance;
  const lngMatch = Math.abs(latLng.lng - originalPoint[1]) < tolerance;
  return latMatch && lngMatch;
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
