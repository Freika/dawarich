import { Controller } from "@hotwired/stimulus"
import L, { circleMarker } from "leaflet"
import "leaflet.heat"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    console.log("Map controller connected")
    var markers = JSON.parse(this.element.dataset.coordinates)
    var center = markers[markers.length - 1] || JSON.parse(this.element.dataset.center)
    var center = (center === undefined) ? [52.516667, 13.383333] : center;

    var map = L.map(this.containerTarget, {
      layers: [this.osmMapLayer(), this.osmHotMapLayer()]
    }).setView([center[0], center[1]], 14);

    var markersArray = this.markersArray(markers);
    var markersLayer = L.layerGroup(markersArray);
    var heatmapMarkers = markers.map(element => [element[0], element[1], 0.3]); // lat, lon, intensity

    // Function to calculate distance between two lat-lng points using Haversine formula
    function haversineDistance(lat1, lon1, lat2, lon2) {
      const toRad = x => x * Math.PI / 180;
      const R = 6371; // Radius of the Earth in kilometers
      const dLat = toRad(lat2 - lat1);
      const dLon = toRad(lon2 - lon1);
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      return R * c * 1000; // Distance in meters
    }

    function addHighlightOnHover(polyline, map, popupContent) {
      // Define the original and highlight styles
      const originalStyle = { color: 'blue', opacity: 0.6, weight: 3 };
      const highlightStyle = { color: 'yellow', opacity: 1, weight: 5 };

      // Apply original style to the polyline initially
      polyline.setStyle(originalStyle);

      // Add mouseover event to highlight the polyline and show the popup
      polyline.on('mouseover', function(e) {
          polyline.setStyle(highlightStyle);
          var popup = L.popup()
              .setLatLng(e.latlng)
              .setContent(popupContent)
              .openOn(map);
      });

      // Add mouseout event to revert the polyline style and close the popup
      polyline.on('mouseout', function(e) {
          polyline.setStyle(originalStyle);
          map.closePopup();
      });
  }


    var splitPolylines = [];
    var currentPolyline = [];

    // Process markers and split polylines based on the distance
    for (let i = 0, len = markers.length; i < len; i++) {
      if (currentPolyline.length === 0) {
        currentPolyline.push(markers[i]);
      } else {
        var lastPoint = currentPolyline[currentPolyline.length - 1];
        var currentPoint = markers[i];
        var distance = haversineDistance(lastPoint[0], lastPoint[1], currentPoint[0], currentPoint[1]);

        if (distance > 500) {
          splitPolylines.push([...currentPolyline]); // Use spread operator to clone the array
          currentPolyline = [currentPoint];
        } else {
          currentPolyline.push(currentPoint);
        }
      }
    }
    // Add the last polyline if it exists
    if (currentPolyline.length > 0) {
      splitPolylines.push(currentPolyline);
    }

    // Assuming each polylineCoordinates is an array of objects with lat, lng, and timestamp properties
    var polylineLayers = splitPolylines.map(polylineCoordinates => {
      // Extract lat-lng pairs for the polyline
      var latLngs = polylineCoordinates.map(point => [point[0], point[1]]);

      // Create a polyline with the given coordinates
      var polyline = L.polyline(latLngs, { color: 'blue', opacity: 0.6, weight: 3 });

      // Get the timestamps of the first and last points
      var firstTimestamp = this.formatDate(polylineCoordinates[0][4]);
      var lastTimestamp = this.formatDate(polylineCoordinates[polylineCoordinates.length - 1][4])

      // Create the popup content
      var popupContent = `Route started: ${firstTimestamp}<br>Route ended: ${lastTimestamp}`;

      addHighlightOnHover(polyline, map, popupContent);

      return polyline;
    });

    var polylinesLayer = L.layerGroup(polylineLayers).addTo(map);

    var heatmapLayer = L.heatLayer(heatmapMarkers, { radius: 20 }).addTo(map);

    var controlsLayer = {
      "Points": markersLayer,
      "Polylines": L.layerGroup(polylineLayers).addTo(map),
      "Heatmap": heatmapLayer
    };

    L.control.layers(this.baseMaps(), controlsLayer).addTo(map);

    this.addTileLayer(map);
    this.addLastMarker(map, markers);
  }

  disconnect() {
    this.map.remove();
  }

  osmMapLayer() {
    return L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© OpenStreetMap'
    })
  }

  osmHotMapLayer() {
    return L.tileLayer('https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© OpenStreetMap contributors, Tiles style by Humanitarian OpenStreetMap Team hosted by OpenStreetMap France'
    })
  }

  baseMaps() {
    return {
      "OpenStreetMap": this.osmMapLayer(),
      "OpenStreetMap.HOT": this.osmHotMapLayer()
    }
  }

  controlsLayer() {
    return {
      "Points": this.markersLayer,
      "Polyline": this.polylineLayer
    }
  }

  markersArray(markers_data) {
    var markersArray = []

    for (var i = 0; i < markers_data.length; i++) {
      var lat = markers_data[i][0];
      var lon = markers_data[i][1];

      var popupContent = this.popupContent(markers_data[i]);
      var circleMarker = L.circleMarker([lat, lon], {radius: 4})

      markersArray.push(circleMarker.bindPopup(popupContent).openPopup())
    }

    return markersArray
  }

  popupContent(marker) {
    return `
      <b>Timestamp:</b> ${this.formatDate(marker[4])}<br>
      <b>Latitude:</b> ${marker[0]}<br>
      <b>Longitude:</b> ${marker[1]}<br>
      <b>Altitude:</b> ${marker[3]}m<br>
      <b>Velocity:</b> ${marker[5]}km/h<br>
      <b>Battery:</b> ${marker[2]}%
    `;
  }

  formatDate(timestamp) {
    let date = new Date(timestamp * 1000); // Multiply by 1000 because JavaScript works with milliseconds

    let timezone = this.element.dataset.timezone;

    return date.toLocaleString('en-GB', { timeZone: timezone });
  }

  addTileLayer(map) {
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);
  }


  addPolyline(map, markers) {
    var coordinates = markers.map(element => element.slice(0, 2));
    L.polyline(coordinates).addTo(map);
  }

  addLastMarker(map, markers) {
    if (markers.length > 0) {
      var lastMarker = markers[markers.length - 1].slice(0, 2)
      L.marker(lastMarker).addTo(map);
    }
  }
}
