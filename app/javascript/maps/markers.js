import { createPopupContent } from "./popups";
import { calculateSpeed, getSpeedColor } from "./polylines";
import { haversineDistance } from "./helpers";

export function createMarkersArray(markersData, userSettings, apiKey, map) {
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
        weight: 3,
        zIndexOffset: 400
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
          html: `<div style="background-color: ${markerColor}; width: 12px; height: 12px; border-radius: 50%;"></div>`,
          iconSize: [12, 12]
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

            // Remove the old polyline
            if (polyline) {
              polyline.remove();
            }

            // Find the polylines layer in the map layers
            let polylinesLayer;
            map.eachLayer((layer) => {
              if (layer instanceof L.LayerGroup && layer.getLayers().some(l => l instanceof L.FeatureGroup)) {
                polylinesLayer = layer;
              }
            });

            if (polylinesLayer) {
              // Update affected segments in all feature groups
              polylinesLayer.eachLayer((featureGroup) => {
                if (featureGroup instanceof L.FeatureGroup) {
                  featureGroup.eachLayer((segment) => {
                    if (segment instanceof L.Polyline) {
                      const segmentLatLngs = segment.getLatLngs();
                      let updated = false;

                      // Check if this segment starts or ends with our point
                      if (Math.abs(segmentLatLngs[0].lat - lat) < 0.0000001 &&
                          Math.abs(segmentLatLngs[0].lng - lon) < 0.0000001) {
                        segmentLatLngs[0] = position;
                        updated = true;
                      }
                      if (Math.abs(segmentLatLngs[1].lat - lat) < 0.0000001 &&
                          Math.abs(segmentLatLngs[1].lng - lon) < 0.0000001) {
                        segmentLatLngs[1] = position;
                        updated = true;
                      }

                      if (updated) {
                        // Update segment position
                        segment.setLatLngs(segmentLatLngs);

                        // Recalculate speed for the segment
                        const point1 = markersData[index];
                        const adjacentIndex = index + (segmentLatLngs[0].equals(position) ? -1 : 1);
                        const point2 = markersData[adjacentIndex];

                        if (point1 && point2) {
                          const speed = calculateSpeed(point1, point2);
                          const color = getSpeedColor(speed, userSettings.speed_colored_routes);
                          segment.setStyle({
                            color: color,
                            originalColor: color,
                            speed: speed
                          });
                        }
                      }
                    }
                  });
                }
              });
            }

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
              if (window.showFlashMessage) {
                window.showFlashMessage('notice', 'Point position updated successfully');
              }
            })
            .catch(error => {
              console.error('Error updating point position:', error);
              if (window.showFlashMessage) {
                window.showFlashMessage('error', 'Failed to update point position');
              }
              // Revert the marker position
              marker.setLatLng([lat, lon]);

              // Revert the polyline segments
              if (polylinesLayer) {
                polylinesLayer.eachLayer((featureGroup) => {
                  if (featureGroup instanceof L.FeatureGroup) {
                    featureGroup.eachLayer((segment) => {
                      if (segment instanceof L.Polyline) {
                        const segmentLatLngs = segment.getLatLngs();
                        if (segmentLatLngs[0].equals(position)) {
                          segmentLatLngs[0] = L.latLng(lat, lon);
                          segment.setLatLngs(segmentLatLngs);
                        }
                        if (segmentLatLngs[1].equals(position)) {
                          segmentLatLngs[1] = L.latLng(lat, lon);
                          segment.setLatLngs(segmentLatLngs);
                        }
                      }
                    });
                  }
                });
              }
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
