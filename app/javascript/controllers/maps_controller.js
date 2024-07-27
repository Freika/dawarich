import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import "leaflet.heat";
import { formatDistance } from "../maps/helpers";
import { getUrlParameter } from "../maps/helpers";
import { minutesToDaysHoursMinutes } from "../maps/helpers";
import { formatDate } from "../maps/helpers";
import { haversineDistance } from "../maps/helpers";
import { osmMapLayer } from "../maps/layers";
import { osmHotMapLayer } from "../maps/layers";
import { addTileLayer } from "../maps/layers";
import "leaflet-draw";

export default class extends Controller {
  static targets = ["container"];

  connect() {
    console.log("Map controller connected");

    this.apiKey = this.element.dataset.api_key;
    this.markers = JSON.parse(this.element.dataset.coordinates);
    this.timezone = this.element.dataset.timezone;
    this.clearFogRadius = this.element.dataset.fog_of_war_meters;

    this.center = this.markers[this.markers.length - 1] || [52.514568, 13.350111];

    this.map = L.map(this.containerTarget, {
      layers: [osmMapLayer(), osmHotMapLayer()],
    }).setView([this.center[0], this.center[1]], 14);

    this.markersArray = this.createMarkersArray(this.markers);
    this.markersLayer = L.layerGroup(this.markersArray);
    this.heatmapMarkers = this.markers.map((element) => [element[0], element[1], 0.3]);

    this.polylinesLayer = this.createPolylinesLayer(this.markers, this.map, this.timezone);
    this.heatmapLayer = L.heatLayer(this.heatmapMarkers, { radius: 20 }).addTo(this.map);
    this.fogOverlay = L.layerGroup(); // Initialize fog layer
    this.areasLayer = L.layerGroup(); // Initialize areas layer

    const controlsLayer = {
      Points: this.markersLayer,
      Polylines: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      Areas: this.areasLayer // Add the areas layer to the controls
    };

    L.control
      .scale({
        position: "bottomright",
        metric: true,
        imperial: false,
        maxWidth: 120,
      })
      .addTo(this.map);

    L.control.layers(this.baseMaps(), controlsLayer).addTo(this.map);

    // Fetch and draw areas when the map is loaded
    this.fetchAndDrawAreas(this.apiKey);

    let fogEnabled = false;

    // Hide fog by default
    document.getElementById('fog').style.display = 'none';

    // Toggle fog layer visibility
    this.map.on('overlayadd', (e) => {
      if (e.name === 'Fog of War') {
        fogEnabled = true;
        document.getElementById('fog').style.display = 'block';
        this.updateFog(this.markers, this.clearFogRadius);
      }
    });

    this.map.on('overlayremove', (e) => {
      if (e.name === 'Fog of War') {
        fogEnabled = false;
        document.getElementById('fog').style.display = 'none';
      }
    });

    // Update fog circles on zoom and move
    this.map.on('zoomend moveend', () => {
      if (fogEnabled) {
        this.updateFog(this.markers, this.clearFogRadius);
      }
    });

    addTileLayer(this.map);
    this.addLastMarker(this.map, this.markers);
    this.addEventListeners();

    // Initialize Leaflet.draw
    this.initializeDrawControl();

    // Add event listeners to toggle draw controls
    this.map.on('overlayadd', (e) => {
      if (e.name === 'Areas') {
        this.map.addControl(this.drawControl);
      }
    });

    this.map.on('overlayremove', (e) => {
      if (e.name === 'Areas') {
        this.map.removeControl(this.drawControl);
      }
    });
  }

  disconnect() {
    this.map.remove();
  }

  baseMaps() {
    return {
      OpenStreetMap: osmMapLayer(),
      "OpenStreetMap.HOT": osmHotMapLayer(),
    };
  }

  createMarkersArray(markersData) {
    return markersData.map((marker) => {
      const [lat, lon] = marker;
      const popupContent = this.createPopupContent(marker);
      return L.circleMarker([lat, lon], { radius: 4 }).bindPopup(popupContent);
    });
  }

  createPopupContent(marker) {
    const timezone = this.element.dataset.timezone;
    return `
      <b>Timestamp:</b> ${formatDate(marker[4], timezone)}<br>
      <b>Latitude:</b> ${marker[0]}<br>
      <b>Longitude:</b> ${marker[1]}<br>
      <b>Altitude:</b> ${marker[3]}m<br>
      <b>Velocity:</b> ${marker[5]}km/h<br>
      <b>Battery:</b> ${marker[2]}%<br>
      <a href="#" data-id="${marker[6]}" class="delete-point">[Delete]</a>
    `;
  }

  addEventListeners() {
    document.addEventListener('click', (event) => {
      if (event.target && event.target.classList.contains('delete-point')) {
        event.preventDefault();
        const pointId = event.target.getAttribute('data-id');

        if (confirm('Are you sure you want to delete this point?')) {
          this.deletePoint(pointId);
        }
      }
    });
  }

  deletePoint(id) {
    fetch(`/api/v1/points/${id}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
      console.log('Point deleted:', data);

      // Remove the marker from the map
      this.removeMarker(id);
    })
    .catch(error => {
      console.error('There was a problem with the delete request:', error);
    });
  }

  removeMarker(id) {
    const markerIndex = this.markersArray.findIndex(marker => marker.getPopup().getContent().includes(`data-id="${id}"`));
    if (markerIndex !== -1) {
      this.markersArray[markerIndex].remove(); // Assuming your marker object has a remove method
      this.markersArray.splice(markerIndex, 1);
      this.markersLayer.clearLayers();
      this.markersLayer.addLayer(L.layerGroup(this.markersArray));

      // Remove from the markers data array
      this.markers = this.markers.filter(marker => marker[6] !== parseInt(id));
    }
  }

  addLastMarker(map, markers) {
    if (markers.length > 0) {
      const lastMarker = markers[markers.length - 1].slice(0, 2);
      L.marker(lastMarker).addTo(map);
    }
  }

  updateFog(markers, clearFogRadius) {
    var fog = document.getElementById('fog');
    fog.innerHTML = ''; // Clear previous circles
    markers.forEach((point) => {
      const radiusInPixels = this.metersToPixels(this.map, clearFogRadius);
      this.clearFog(point[0], point[1], radiusInPixels);
    });
  }

  metersToPixels(map, meters) {
    const zoom = map.getZoom();
    const latLng = map.getCenter(); // Get map center for correct projection
    const metersPerPixel = this.getMetersPerPixel(latLng.lat, zoom);
    return meters / metersPerPixel;
  }

  getMetersPerPixel(latitude, zoom) {
    const earthCircumference = 40075016.686; // Earth's circumference in meters
    const metersPerPixel = earthCircumference * Math.cos(latitude * Math.PI / 180) / Math.pow(2, zoom + 8);
    return metersPerPixel;
  }

  clearFog(lat, lng, radius) {
    var fog = document.getElementById('fog');
    var point = this.map.latLngToContainerPoint([lat, lng]);
    var size = radius * 2;
    var circle = document.createElement('div');
    circle.className = 'unfogged-circle';
    circle.style.width = size + 'px';
    circle.style.height = size + 'px';
    circle.style.left = (point.x - radius) + 'px';
    circle.style.top = (point.y - radius) + 'px';
    circle.style.backdropFilter = 'blur(0px)'; // Remove blur for the circles
    fog.appendChild(circle);
  }

  addHighlightOnHover(polyline, map, polylineCoordinates, timezone) {
    const originalStyle = { color: "blue", opacity: 0.6, weight: 3 };
    const highlightStyle = { color: "yellow", opacity: 1, weight: 5 };

    polyline.setStyle(originalStyle);

    const startPoint = polylineCoordinates[0];
    const endPoint = polylineCoordinates[polylineCoordinates.length - 1];

    const firstTimestamp = new Date(startPoint[4] * 1000).toLocaleString("en-GB", { timeZone: timezone });
    const lastTimestamp = new Date(endPoint[4] * 1000).toLocaleString("en-GB", { timeZone: timezone });

    const minutes = Math.round((endPoint[4] - startPoint[4]) / 60);
    const timeOnRoute = minutesToDaysHoursMinutes(minutes);

    const totalDistance = polylineCoordinates.reduce((acc, curr, index, arr) => {
      if (index === 0) return acc;
      const dist = haversineDistance(arr[index - 1][0], arr[index - 1][1], curr[0], curr[1]);
      return acc + dist;
    }, 0);

    const startIcon = L.divIcon({ html: "🚥", className: "emoji-icon" });
    const finishIcon = L.divIcon({ html: "🏁", className: "emoji-icon" });

    const isDebugMode = getUrlParameter("debug") === "true";

    let popupContent = `
      <b>Start:</b> ${firstTimestamp}<br>
      <b>End:</b> ${lastTimestamp}<br>
      <b>Duration:</b> ${timeOnRoute}<br>
      <b>Total Distance:</b> ${formatDistance(totalDistance)}<br>
    `;

    if (isDebugMode) {
      const prevPoint = polylineCoordinates[0];
      const nextPoint = polylineCoordinates[polylineCoordinates.length - 1];
      const distanceToPrev = haversineDistance(prevPoint[0], prevPoint[1], startPoint[0], startPoint[1]);
      const distanceToNext = haversineDistance(endPoint[0], endPoint[1], nextPoint[0], nextPoint[1]);

      const timeBetweenPrev = Math.round((startPoint[4] - prevPoint[4]) / 60);
      const timeBetweenNext = Math.round((endPoint[4] - nextPoint[4]) / 60);

      popupContent += `
        <b>Prev Route:</b> ${Math.round(distanceToPrev)}m and ${minutesToDaysHoursMinutes(timeBetweenPrev)} away<br>
        <b>Next Route:</b> ${Math.round(distanceToNext)}m and ${minutesToDaysHoursMinutes(timeBetweenNext)} away<br>
      `;
    }

    const startMarker = L.marker([startPoint[0], startPoint[1]], { icon: startIcon }).bindPopup(`Start: ${firstTimestamp}`);
    const endMarker = L.marker([endPoint[0], endPoint[1]], { icon: finishIcon }).bindPopup(popupContent);

    let hoverPopup = null;

    polyline.on("mouseover", function (e) {
      polyline.setStyle(highlightStyle);
      startMarker.addTo(map);
      endMarker.addTo(map);

      const latLng = e.latlng;
      if (hoverPopup) {
        map.closePopup(hoverPopup);
      }
      hoverPopup = L.popup()
        .setLatLng(latLng)
        .setContent(popupContent)
        .openOn(map);
    });

    polyline.on("mouseout", function () {
      polyline.setStyle(originalStyle);
      map.closePopup(hoverPopup);
      map.removeLayer(startMarker);
      map.removeLayer(endMarker);
    });

    polyline.on("click", function () {
      map.fitBounds(polyline.getBounds());
    });

    // Close the popup when clicking elsewhere on the map
    map.on("click", function () {
      map.closePopup(hoverPopup);
    });
  }

  createPolylinesLayer(markers, map, timezone) {
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

        this.addHighlightOnHover(polyline, map, polylineCoordinates, timezone);

        return polyline;
      })
    ).addTo(map);
  }

  initializeDrawControl() {
    // Initialize the FeatureGroup to store editable layers
    this.drawnItems = new L.FeatureGroup();
    this.map.addLayer(this.drawnItems);

    // Initialize the draw control and pass it the FeatureGroup of editable layers
    this.drawControl = new L.Control.Draw({
      draw: {
        polyline: false,
        polygon: false,
        rectangle: false,
        marker: false,
        circlemarker: false,
        circle: {
          shapeOptions: {
            color: 'red',
            fillColor: '#f03',
            fillOpacity: 0.5,
          },
        },
      },
    });

    // Handle circle creation
    this.map.on(L.Draw.Event.CREATED, (event) => {
      const layer = event.layer;

      if (event.layerType === 'circle') {
        this.handleCircleCreated(layer);
      }

      this.drawnItems.addLayer(layer);
    });
  }

  handleCircleCreated(layer) {
    const radius = layer.getRadius();
    const center = layer.getLatLng();

    const formHtml = `
      <div class="card w-96 max-w-sm bg-content-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">New Area</h2>
          <form id="circle-form">
            <div class="form-control">
              <label for="circle-name" class="label">
                <span class="label-text">Name</span>
              </label>
              <input type="text" id="circle-name" name="area[name]" class="input input-bordered input-ghost focus:input-ghost w-full max-w-xs" required>
            </div>
            <input type="hidden" name="area[latitude]" value="${center.lat}">
            <input type="hidden" name="area[longitude]" value="${center.lng}">
            <input type="hidden" name="area[radius]" value="${radius}">
            <div class="card-actions justify-end mt-4">
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </form>
        </div>
      </div>
    `;

    layer.bindPopup(
      formHtml, {
        maxWidth: "auto",
        minWidth: 300
      }
     ).openPopup();

    layer.on('popupopen', () => {
      const form = document.getElementById('circle-form');
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        this.saveCircle(new FormData(form), layer, this.apiKey);
      });
    });

    // Add the layer to the areas layer group
    this.areasLayer.addLayer(layer);
  }

  saveCircle(formData, layer, apiKey) {
    const data = {};
    formData.forEach((value, key) => {
      const keys = key.split('[').map(k => k.replace(']', ''));
      if (keys.length > 1) {
        if (!data[keys[0]]) data[keys[0]] = {};
        data[keys[0]][keys[1]] = value;
      } else {
        data[keys[0]] = value;
      }
    });

    fetch(`/api/v1/areas?api_key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json'},
      body: JSON.stringify(data)
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
      console.log('Circle saved:', data);
      layer.closePopup();
      layer.bindPopup(`
        Name: ${data.name}<br>
        Radius: ${Math.round(data.radius)} meters<br>
        <a href="#" data-id="${marker[6]}" class="delete-area">[Delete]</a>
      `).openPopup();

      // Add event listener for the delete button
      layer.on('popupopen', () => {
        document.querySelector('.delete-area').addEventListener('click', () => {
          this.deleteArea(data.id, layer);
        });
      });
    })
    .catch(error => {
      console.error('There was a problem with the save request:', error);
    });
  }

  deleteArea(id, layer, apiKey) {
    fetch(`/api/v1/areas/${id}?api_key=${apiKey}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
      console.log('Area deleted:', data);
      this.areasLayer.removeLayer(layer); // Remove the layer from the areas layer group
    })
    .catch(error => {
      console.error('There was a problem with the delete request:', error);
    });
  }

  fetchAndDrawAreas(apiKey) {
    fetch(`/api/v1/areas?api_key=${apiKey}`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json'
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
      console.log('Fetched areas:', data); // Debugging line to check response

      data.forEach(area => {
        // Log each area to verify the structure
        console.log('Area:', area);

        // Check if necessary fields are present
        if (area.latitude && area.longitude && area.radius && area.name && area.id) {
          const layer = L.circle([area.latitude, area.longitude], {
            radius: area.radius,
            color: 'red',
            fillColor: '#f03',
            fillOpacity: 0.5
          }).bindPopup(`
            Name: ${area.name}<br>
            Radius: ${Math.round(area.radius)} meters<br>
            <a href="#" data-id="${area.id}" class="delete-area">[Delete]</a>
          `);

          this.areasLayer.addLayer(layer); // Add to areas layer group
          console.log('Added layer to areasLayer:', layer); // Debugging line to confirm addition

          // Add event listener for the delete button
          layer.on('popupopen', () => {
            document.querySelector('.delete-area').addEventListener('click', (e) => {
              e.preventDefault();
              if (confirm('Are you sure you want to delete this area?')) {
                this.deleteArea(area.id, layer, this.apiKey);
              }
            });
          });
        } else {
          console.error('Area missing required fields:', area);
        }
      });
    })
    .catch(error => {
      console.error('There was a problem with the fetch request:', error);
    });
  }
}
