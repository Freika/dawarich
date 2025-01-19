import { createPopupContent } from "./popups";

export function createMarkersArray(markersData, userSettings, apiKey) {
  // Create a canvas renderer
  const renderer = L.canvas({ padding: 0.5 });

  if (userSettings.pointsRenderingMode === "simplified") {
    return createSimplifiedMarkers(markersData, renderer);
  } else {
    return markersData.map((marker, index) => {
      const [lat, lon] = marker;
      const pointId = marker[2];
      const popupContent = createPopupContent(marker, userSettings.timezone, userSettings.distanceUnit);
      let markerColor = marker[5] < 0 ? "orange" : "blue";

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
        renderer: renderer
      }).bindPopup(popupContent)
        .on('dragstart', function(e) {
          console.log('Drag started', { index: this.options.pointIndex });
          this.closePopup();
        })
        .on('drag', function(e) {
          const newLatLng = e.target.getLatLng();
          const map = e.target._map;
          const pointIndex = e.target.options.pointIndex;
          const originalLat = e.target.options.originalLat;
          const originalLng = e.target.options.originalLng;

          console.log('Dragging point', {
            pointIndex,
            newPosition: newLatLng,
            originalPosition: { lat: originalLat, lng: originalLng }
          });

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
                        console.log('Updating start point of segment', {
                          from: coords[0],
                          to: newLatLng
                        });
                        coords[0] = newLatLng;
                        updated = true;
                      }

                      // Check and update end point
                      if (Math.abs(coords[1].lat - originalLat) < tolerance &&
                          Math.abs(coords[1].lng - originalLng) < tolerance) {
                        console.log('Updating end point of segment', {
                          from: coords[1],
                          to: newLatLng
                        });
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
          console.log('Drag ended', {
            finalPosition: e.target.getLatLng(),
            pointIndex: e.target.options.pointIndex
          });
          const newLatLng = e.target.getLatLng();
          const pointId = e.target.options.pointId;
          const pointIndex = e.target.options.pointIndex;

          // Update the marker's position
          this.setLatLng(newLatLng);
          this.openPopup();

          // Send API request to update point position
          fetch(`/api/v1/points/${pointId}`, {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': `Bearer ${apiKey}`
            },
            body: JSON.stringify({
              point: {
                latitude: newLatLng.lat,
                longitude: newLatLng.lng
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
            // Update the markers array in the controller
            const map = e.target._map;
            const mapsController = map.mapsController;
            if (mapsController && mapsController.markers) {
              mapsController.markers[pointIndex][0] = newLatLng.lat;
              mapsController.markers[pointIndex][1] = newLatLng.lng;

              // Store current polylines visibility state
              const wasPolyLayerVisible = map.hasLayer(mapsController.polylinesLayer);

              // Remove old polylines layer
              if (mapsController.polylinesLayer) {
                map.removeLayer(mapsController.polylinesLayer);
              }

              // Create new polylines layer with updated coordinates
              mapsController.polylinesLayer = createPolylinesLayer(
                mapsController.markers,
                map,
                mapsController.timezone,
                mapsController.routeOpacity,
                mapsController.userSettings,
                mapsController.distanceUnit
              );

              // Restore polylines visibility if it was visible before
              if (wasPolyLayerVisible) {
                mapsController.polylinesLayer.addTo(map);
              }
            }

            // Update popup content with new data
            const updatedPopupContent = createPopupContent(
              [
                data.latitude,
                data.longitude,
                data.id,
                data.altitude,
                data.timestamp,
                data.velocity || 0
              ],
              userSettings.timezone,
              userSettings.distanceUnit
            );
            this.setPopupContent(updatedPopupContent);
          })
          .catch(error => {
            console.error('Error updating point position:', error);
            // Revert the marker position on error
            this.setLatLng([lat, lon]);
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
