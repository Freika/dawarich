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
    var timezone = this.element.dataset.timezone;

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

    function getURLParameter(name) {
      return new URLSearchParams(window.location.search).get(name);
    }

    function addHighlightOnHover(polyline, map, startPoint, endPoint, prevPoint, nextPoint, timezone) {
      // Define the original and highlight styles
      const originalStyle = { color: 'blue', opacity: 0.6, weight: 3 };
      const highlightStyle = { color: 'yellow', opacity: 1, weight: 5 };

      // Apply original style to the polyline initially
      polyline.setStyle(originalStyle);

      // Create the popup content for the route
      var firstTimestamp = new Date(startPoint[4] * 1000).toLocaleString('en-GB', { timeZone: timezone });
      var lastTimestamp = new Date(endPoint[4] * 1000).toLocaleString('en-GB', { timeZone: timezone });
      var timeOnRoute = Math.round((endPoint[4] - startPoint[4]) / 60); // Time in minutes

      // Calculate distances to previous and next points
      var distanceToPrev = prevPoint ? haversineDistance(prevPoint[0], prevPoint[1], startPoint[0], startPoint[1]) : 'N/A';
      var distanceToNext = nextPoint ? haversineDistance(endPoint[0], endPoint[1], nextPoint[0], nextPoint[1]) : 'N/A';

      // Calculate time between routes
      var timeBetweenPrev = prevPoint ? Math.round((startPoint[4] - prevPoint[4]) / 60) : 'N/A';
      var timeBetweenNext = nextPoint ? Math.round((nextPoint[4] - endPoint[4]) / 60) : 'N/A';

      // Create custom emoji icons
      const startIcon = L.divIcon({ html: '🚥', className: 'emoji-icon' });
      const finishIcon = L.divIcon({ html: '🏁', className: 'emoji-icon' });

      // Create markers for the start and end points
      const startMarker = L.marker([startPoint[0], startPoint[1]], { icon: startIcon }).bindPopup(`Start: ${firstTimestamp}`);
      const endMarker = L.marker([endPoint[0], endPoint[1]], { icon: finishIcon }).bindPopup(`
        <b>Start:</b> ${firstTimestamp}<br>
        <b>End:</b> ${lastTimestamp}<br>
        <b>Duration:</b> ${timeOnRoute} min<br>
        <b>Prev Route:</b> ${Math.round(distanceToPrev)} m, ${timeBetweenPrev} min away<br>
        <b>Next Route:</b> ${Math.round(distanceToNext)} m, ${timeBetweenNext} min away<br>
      `);

      // Add mouseover event to highlight the polyline and show the start and end markers
      polyline.on('mouseover', function(e) {
        polyline.setStyle(highlightStyle);
        startMarker.addTo(map);
        endMarker.addTo(map).openPopup();
      });

      // Add mouseout event to revert the polyline style and remove the start and end markers
      polyline.on('mouseout', function(e) {
        polyline.setStyle(originalStyle);
        map.closePopup();
        map.removeLayer(startMarker);
        map.removeLayer(endMarker);
      });
    }

    var splitPolylines = [];
    var currentPolyline = [];
    var distanceThresholdMeters = parseInt(getURLParameter('meters_between_routes')) || 500;
    var timeThresholdMinutes = parseInt(getURLParameter('minutes_between_routes')) || 60;

    // Process markers and split polylines based on the distance and time
    for (let i = 0, len = markers.length; i < len; i++) {
      if (currentPolyline.length === 0) {
        currentPolyline.push(markers[i]);
      } else {
        var lastPoint = currentPolyline[currentPolyline.length - 1];
        var currentPoint = markers[i];
        var distance = haversineDistance(lastPoint[0], lastPoint[1], currentPoint[0], currentPoint[1]);
        var timeDifference = (currentPoint[4] - lastPoint[4]) / 60; // Time difference in minutes

        if (distance > distanceThresholdMeters || timeDifference > timeThresholdMinutes) {
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
    var polylineLayers = splitPolylines.map((polylineCoordinates, index) => {
      // Extract lat-lng pairs for the polyline
      var latLngs = polylineCoordinates.map(point => [point[0], point[1]]);

      // Create a polyline with the given coordinates
      var polyline = L.polyline(latLngs, { color: 'blue', opacity: 0.6, weight: 3 });

      // Get the start and end points
      var startPoint = polylineCoordinates[0];
      var endPoint = polylineCoordinates[polylineCoordinates.length - 1];

      // Get the previous and next points
      var prevPoint = index > 0 ? splitPolylines[index - 1][splitPolylines[index - 1].length - 1] : null;
      var nextPoint = index < splitPolylines.length - 1 ? splitPolylines[index + 1][0] : null;

      // Add highlighting and popups on hover
      addHighlightOnHover(polyline, map, startPoint, endPoint, prevPoint, nextPoint, timezone);

      return polyline;
    });

    var polylinesLayer = L.layerGroup(polylineLayers).addTo(map);
    var heatmapLayer = L.heatLayer(heatmapMarkers, { radius: 20 }).addTo(map);

    var controlsLayer = {
      "Points": markersLayer,
      "Polylines": polylinesLayer,
      "Heatmap": heatmapLayer
    };

    L.control.scale({
      position: 'bottomright', // The default position is 'bottomleft'
      metric: true, // Display metric scale
      imperial: false, // Display imperial scale
      maxWidth: 120 // Maximum width of the scale control in pixels
    }).addTo(map);

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
