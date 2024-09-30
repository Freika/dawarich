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
import { OPNVMapLayer } from "../maps/layers";
import { openTopoMapLayer } from "../maps/layers";
// import { stadiaAlidadeSmoothMapLayer } from "../maps/layers";
// import { stadiaAlidadeSmoothDarkMapLayer } from "../maps/layers";
// import { stadiaAlidadeSatelliteMapLayer } from "../maps/layers";
// import { stadiaOsmBrightMapLayer } from "../maps/layers";
// import { stadiaOutdoorMapLayer } from "../maps/layers";
// import { stadiaStamenTonerMapLayer } from "../maps/layers";
// import { stadiaStamenTonerBackgroundMapLayer } from "../maps/layers";
// import { stadiaStamenTonerLiteMapLayer } from "../maps/layers";
// import { stadiaStamenWatercolorMapLayer } from "../maps/layers";
// import { stadiaStamenTerrainMapLayer } from "../maps/layers";
import { cyclOsmMapLayer } from "../maps/layers";
import { esriWorldStreetMapLayer } from "../maps/layers";
import { esriWorldTopoMapLayer } from "../maps/layers";
import { esriWorldImageryMapLayer } from "../maps/layers";
import { esriWorldGrayCanvasMapLayer } from "../maps/layers";
import "leaflet-draw";

export default class extends Controller {
  static targets = ["container"];

  settingsButtonAdded = false;
  layerControl = null;

  connect() {
    console.log("Map controller connected");

    this.apiKey = this.element.dataset.api_key;
    this.markers = JSON.parse(this.element.dataset.coordinates);
    this.timezone = this.element.dataset.timezone;
    this.userSettings = JSON.parse(this.element.dataset.user_settings);
    this.clearFogRadius = parseInt(this.userSettings.fog_of_war_meters) || 50;
    this.routeOpacity = parseFloat(this.userSettings.route_opacity) || 0.6;
    this.distanceUnit = this.element.dataset.distance_unit || "km";

    this.center = this.markers[this.markers.length - 1] || [52.514568, 13.350111];

    this.map = L.map(this.containerTarget).setView([this.center[0], this.center[1]], 14);

    this.markersArray = this.createMarkersArray(this.markers);
    this.markersLayer = L.layerGroup(this.markersArray);
    this.heatmapMarkers = this.markers.map((element) => [element[0], element[1], 0.2]);

    this.polylinesLayer = this.createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity);
    this.heatmapLayer = L.heatLayer(this.heatmapMarkers, { radius: 20 }).addTo(this.map);
    this.fogOverlay = L.layerGroup(); // Initialize fog layer
    this.areasLayer = L.layerGroup(); // Initialize areas layer

    if (!this.settingsButtonAdded) {
      this.addSettingsButton();
    }

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

    this.layerControl = L.control.layers(this.baseMaps(), controlsLayer).addTo(this.map);

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
    let selectedLayerName = this.userSettings.preferred_map_layer || "OpenStreetMap";
console.log(selectedLayerName);
    return {
      OpenStreetMap: osmMapLayer(this.map, selectedLayerName),
      "OpenStreetMap.HOT": osmHotMapLayer(this.map, selectedLayerName),
      OPNV: OPNVMapLayer(this.map, selectedLayerName),
      openTopo: openTopoMapLayer(this.map, selectedLayerName),
      // stadiaAlidadeSmooth: stadiaAlidadeSmoothMapLayer(this.map, selectedLayerName),
      // stadiaAlidadeSmoothDark: stadiaAlidadeSmoothDarkMapLayer(this.map, selectedLayerName),
      // stadiaAlidadeSatellite: stadiaAlidadeSatelliteMapLayer(this.map, selectedLayerName),
      // stadiaOsmBright: stadiaOsmBrightMapLayer(this.map, selectedLayerName),
      // stadiaOutdoor: stadiaOutdoorMapLayer(this.map, selectedLayerName),
      // stadiaStamenToner: stadiaStamenTonerMapLayer(this.map, selectedLayerName),
      // stadiaStamenTonerBackground: stadiaStamenTonerBackgroundMapLayer(this.map, selectedLayerName),
      // stadiaStamenTonerLite: stadiaStamenTonerLiteMapLayer(this.map, selectedLayerName),
      // stadiaStamenWatercolor: stadiaStamenWatercolorMapLayer(this.map, selectedLayerName),
      // stadiaStamenTerrain: stadiaStamenTerrainMapLayer(this.map, selectedLayerName),
      cyclOsm: cyclOsmMapLayer(this.map, selectedLayerName),
      esriWorldStreet: esriWorldStreetMapLayer(this.map, selectedLayerName),
      esriWorldTopo: esriWorldTopoMapLayer(this.map, selectedLayerName),
      esriWorldImagery: esriWorldImageryMapLayer(this.map, selectedLayerName),
      esriWorldGrayCanvas: esriWorldGrayCanvasMapLayer(this.map, selectedLayerName)
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
    if (this.distanceUnit === "mi") {
      // convert marker[5] from km/h to mph
      marker[5] = marker[5] * 0.621371;
      // convert marker[3] from meters to feet
      marker[3] = marker[3] * 3.28084;
    }

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

  removeEventListeners() {
    document.removeEventListener('click', this.handleDeleteClick);
  }

  addEventListeners() {
    this.handleDeleteClick = (event) => {
      if (event.target && event.target.classList.contains('delete-point')) {
        event.preventDefault();
        const pointId = event.target.getAttribute('data-id');

        if (confirm('Are you sure you want to delete this point?')) {
          this.deletePoint(pointId, this.apiKey);
        }
      }
    };

    // Ensure only one listener is attached by removing any existing ones first
    this.removeEventListeners();
    document.addEventListener('click', this.handleDeleteClick);

    // Add an event listener for base layer change in Leaflet
    this.map.on('baselayerchange', (event) => {
      const selectedLayerName = event.name;
      this.updatePreferredBaseLayer(selectedLayerName);
    });
  }

  updatePreferredBaseLayer(selectedLayerName) {
    fetch(`/api/v1/settings?api_key=${this.apiKey}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        settings: {
          preferred_map_layer: selectedLayerName
        },
      }),
    })
    .then((response) => response.json())
    .then((data) => {
      if (data.status === 'success') {
        this.showFlashMessage('notice', `Preferred map layer updated to: ${selectedLayerName}`);
      } else {
        this.showFlashMessage('error', data.message);
      }
    });
  }

  deletePoint(id, apiKey) {
    fetch(`/api/v1/points/${id}?api_key=${apiKey}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
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

  addHighlightOnHover(polyline, map, polylineCoordinates, timezone, routeOpacity) {
    const originalStyle = { color: "blue", opacity: routeOpacity, weight: 3 };
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
      <b>Total Distance:</b> ${formatDistance(totalDistance, this.distanceUnit)}<br>
    `;

    if (isDebugMode) {
      const prevPoint = polylineCoordinates[0];
      const nextPoint = polylineCoordinates[polylineCoordinates.length - 1];
      const distanceToPrev = haversineDistance(prevPoint[0], prevPoint[1], startPoint[0], startPoint[1]);
      const distanceToNext = haversineDistance(endPoint[0], endPoint[1], nextPoint[0], nextPoint[1]);

      const timeBetweenPrev = Math.round((startPoint[4] - prevPoint[4]) / 60);
      const timeBetweenNext = Math.round((endPoint[4] - nextPoint[4]) / 60);
      const pointsNumber = polylineCoordinates.length;

      popupContent += `
        <b>Prev Route:</b> ${Math.round(distanceToPrev)}m and ${minutesToDaysHoursMinutes(timeBetweenPrev)} away<br>
        <b>Next Route:</b> ${Math.round(distanceToNext)}m and ${minutesToDaysHoursMinutes(timeBetweenNext)} away<br>
        <b>Points:</b> ${pointsNumber}<br>
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

  createPolylinesLayer(markers, map, timezone, routeOpacity) {
    const splitPolylines = [];
    let currentPolyline = [];
    const distanceThresholdMeters = parseInt(this.userSettings.meters_between_routes) || 500;
    const timeThresholdMinutes = parseInt(this.userSettings.minutes_between_routes) || 60;

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
      splitPolylines.map((polylineCoordinates) => {
        const latLngs = polylineCoordinates.map((point) => [point[0], point[1]]);
        const polyline = L.polyline(latLngs, { color: "blue", opacity: 0.6, weight: 3 });

        this.addHighlightOnHover(polyline, map, polylineCoordinates, timezone, routeOpacity);

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
      data.forEach(area => {
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

  addSettingsButton() {
    if (this.settingsButtonAdded) return;

    // Define the custom control
    const SettingsControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'map-settings-button');
        button.innerHTML = '⚙️'; // Gear icon

        // Style the button
        button.style.backgroundColor = 'white';
        button.style.width = '32px';
        button.style.height = '32px';
        button.style.border = 'none';
        button.style.cursor = 'pointer';
        button.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';

        // Disable map interactions when clicking the button
        L.DomEvent.disableClickPropagation(button);

        // Toggle settings menu on button click
        L.DomEvent.on(button, 'click', () => {
          this.toggleSettingsMenu();
        });

        return button;
      }
    });

    // Add the control to the map
    this.map.addControl(new SettingsControl({ position: 'topleft' }));
    this.settingsButtonAdded = true;
  }

  toggleSettingsMenu() {
    // If the settings panel already exists, just show/hide it
    if (this.settingsPanel) {
      if (this.settingsPanel._map) {
        this.map.removeControl(this.settingsPanel);
      } else {
        this.map.addControl(this.settingsPanel);
      }
      return;
    }

    // Create the settings panel for the first time
    this.settingsPanel = L.control({ position: 'topleft' });

    this.settingsPanel.onAdd = () => {
      const div = L.DomUtil.create('div', 'leaflet-settings-panel');

      // Form HTML
      div.innerHTML = `
        <form id="settings-form" class="w-48">
          <label for="route-opacity">Route Opacity</label>
          <div class="join">
            <input type="number" class="input input-ghost join-item focus:input-ghost input-xs input-bordered w-full max-w-xs" id="route-opacity" name="route_opacity" min="0" max="1" step="0.1" value="${this.routeOpacity}">
            <label for="route_opacity_info" class="btn-xs join-item ">?</label>

          </div>

          <label for="fog_of_war_meters">Fog of War radius</label>
          <div class="join">
            <input type="number" class="join-item input input-ghost focus:input-ghost input-xs input-bordered w-full max-w-xs" id="fog_of_war_meters" name="fog_of_war_meters" min="5" max="100" step="1" value="${this.clearFogRadius}">
            <label for="fog_of_war_meters_info" class="btn-xs join-item">?</label>
          </div>


          <label for="meters_between_routes">Meters between routes</label>
          <div class="join">
            <input type="number" class="join-item input input-ghost focus:input-ghost input-xs input-bordered w-full max-w-xs" id="meters_between_routes" name="meters_between_routes" step="1" value="${this.userSettings.meters_between_routes}">
            <label for="meters_between_routes_info" class="btn-xs join-item">?</label>
          </div>


          <label for="minutes_between_routes">Minutes between routes</label>
          <div class="join">
            <input type="number" class="join-item input input-ghost focus:input-ghost input-xs input-bordered w-full max-w-xs" id="minutes_between_routes" name="minutes_between_routes" step="1" value="${this.userSettings.minutes_between_routes}">
            <label for="minutes_between_routes_info" class="btn-xs join-item">?</label>
          </div>


          <label for="time_threshold_minutes">Time threshold minutes</label>
          <div class="join">
            <input type="number" class="join-item input input-ghost focus:input-ghost input-xs input-bordered w-full max-w-xs" id="time_threshold_minutes" name="time_threshold_minutes" step="1" value="${this.userSettings.time_threshold_minutes}">
            <label for="time_threshold_minutes_info" class="btn-xs join-item">?</label>
          </div>


          <label for="merge_threshold_minutes">Merge threshold minutes</label>
          <div class="join">
            <input type="number" class="join-item input input-ghost focus:input-ghost input-xs input-bordered w-full max-w-xs" id="merge_threshold_minutes" name="merge_threshold_minutes" step="1" value="${this.userSettings.merge_threshold_minutes}">
            <label for="merge_threshold_minutes_info" class="btn-xs join-item">?</label>
          </div>



          <button type="submit">Update</button>
        </form>
      `;

      // Style the panel
      div.style.backgroundColor = 'white';
      div.style.padding = '10px';
      div.style.border = '1px solid #ccc';
      div.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';

      // Prevent map interactions when interacting with the form
      L.DomEvent.disableClickPropagation(div);

      // Add event listener to the form submission
      div.querySelector('#settings-form').addEventListener(
        'submit', this.updateSettings.bind(this)
      );

      return div;
    };

    this.map.addControl(this.settingsPanel);
  }

  updateSettings(event) {
    event.preventDefault();

    fetch(`/api/v1/settings?api_key=${this.apiKey}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        settings: {
          route_opacity: event.target.route_opacity.value,
          fog_of_war_meters: event.target.fog_of_war_meters.value,
          meters_between_routes: event.target.meters_between_routes.value,
          minutes_between_routes: event.target.minutes_between_routes.value,
          time_threshold_minutes: event.target.time_threshold_minutes.value,
          merge_threshold_minutes: event.target.merge_threshold_minutes.value,
        },
      }),
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.status === 'success') {
          this.showFlashMessage('notice', data.message);
          this.updateMapWithNewSettings(data.settings);
        } else {
          this.showFlashMessage('error', data.message);
        }
      });
  }

  showFlashMessage(type, message) {
    // Create the outer flash container div
    const flashDiv = document.createElement('div');
    flashDiv.setAttribute('data-controller', 'removals');
    flashDiv.className = `flex items-center fixed top-5 right-5 ${this.classesForFlash(type)} py-3 px-5 rounded-lg`;

    // Create the message div
    const messageDiv = document.createElement('div');
    messageDiv.className = 'mr-4';
    messageDiv.innerText = message;

    // Create the close button
    const closeButton = document.createElement('button');
    closeButton.setAttribute('type', 'button');
    closeButton.setAttribute('data-action', 'click->removals#remove');

    // Create the SVG icon for the close button
    const closeIcon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    closeIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    closeIcon.setAttribute('class', 'h-6 w-6');
    closeIcon.setAttribute('fill', 'none');
    closeIcon.setAttribute('viewBox', '0 0 24 24');
    closeIcon.setAttribute('stroke', 'currentColor');

    const closeIconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    closeIconPath.setAttribute('stroke-linecap', 'round');
    closeIconPath.setAttribute('stroke-linejoin', 'round');
    closeIconPath.setAttribute('stroke-width', '2');
    closeIconPath.setAttribute('d', 'M6 18L18 6M6 6l12 12');

    // Append the path to the SVG
    closeIcon.appendChild(closeIconPath);
    // Append the SVG to the close button
    closeButton.appendChild(closeIcon);

    // Append the message and close button to the flash div
    flashDiv.appendChild(messageDiv);
    flashDiv.appendChild(closeButton);

    // Append the flash message to the body or a specific flash container
    document.body.appendChild(flashDiv);

    // Optional: Automatically remove the flash message after 5 seconds
    setTimeout(() => {
      flashDiv.remove();
    }, 5000);
  }

  // Helper function to get flash classes based on type
  classesForFlash(type) {
    switch (type) {
      case 'error':
        return 'bg-red-100 text-red-700 border-red-300';
      case 'notice':
        return 'bg-blue-100 text-blue-700 border-blue-300';
      default:
        return 'bg-blue-100 text-blue-700 border-blue-300';
    }
  }

  updateMapWithNewSettings(newSettings) {
    const currentLayerStates = this.getLayerControlStates();

    // Update local state with new settings
    this.clearFogRadius = parseInt(newSettings.fog_of_war_meters) || 50;
    this.routeOpacity = parseFloat(newSettings.route_opacity) || 0.6;

    // Preserve existing layer instances if they exist
    const preserveLayers = {
      Points:       this.markersLayer,
      Polylines:    this.polylinesLayer,
      Heatmap:      this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      Areas:        this.areasLayer,
    };

    // Clear all layers except base layers
    this.map.eachLayer((layer) => {
      if (!(layer instanceof L.TileLayer)) {
        this.map.removeLayer(layer);
      }
    });

    // Recreate layers only if they don't exist
    this.markersLayer = preserveLayers.Points       || L.layerGroup(this.createMarkersArray(this.markers));
    this.polylinesLayer = preserveLayers.Polylines  || this.createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity);
    this.heatmapLayer = preserveLayers.Heatmap      || L.heatLayer(this.markers.map((element) => [element[0], element[1], 0.2]), { radius: 20 });
    this.fogOverlay = preserveLayers["Fog of War"]  || L.layerGroup();
    this.areasLayer = preserveLayers.Areas          || L.layerGroup();

    // Redraw areas
    this.fetchAndDrawAreas(this.apiKey);

    let fogEnabled = false;
    document.getElementById('fog').style.display = 'none';

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

    this.map.on('zoomend moveend', () => {
      if (fogEnabled) {
        this.updateFog(this.markers, this.clearFogRadius);
      }
    });

    this.addLastMarker(this.map, this.markers);
    this.addEventListeners();
    this.initializeDrawControl();
    this.updatePolylinesOpacity(this.routeOpacity);

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

    this.applyLayerControlStates(currentLayerStates);
  }

  getLayerControlStates() {
    const controls = {};

    this.map.eachLayer((layer) => {
      const layerName = this.getLayerName(layer);

      if (layerName) {
        controls[layerName] = this.map.hasLayer(layer);
      }
    });

    return controls;
  }

  getLayerName(layer) {
    const controlLayers = {
      Points: this.markersLayer,
      Polylines: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      Areas: this.areasLayer,
    };

    for (const [name, val] of Object.entries(controlLayers)) {
      if (val && val.hasLayer && layer && val.hasLayer(layer)) // Check if the group layer contains the current layer
        return name;
    }

    // Direct instance matching
    for (const [name, val] of Object.entries(controlLayers)) {
      if (val === layer) return name;
    }

    return undefined; // Indicate no matching layer name found
  }


  applyLayerControlStates(states) {
    const layerControl = {
      Points: this.markersLayer,
      Polylines: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      Areas: this.areasLayer,
    };

    for (const [name, isVisible] of Object.entries(states)) {
      const layer = layerControl[name];

      if (isVisible && !this.map.hasLayer(layer)) {
        this.map.addLayer(layer);
      } else if (this.map.hasLayer(layer)) {
        this.map.removeLayer(layer);
      }
    }

    // Ensure the layer control reflects the current state
    this.map.removeControl(this.layerControl);
    this.layerControl = L.control.layers(this.baseMaps(), layerControl).addTo(this.map);
  }

  updatePolylinesOpacity(opacity) {
    this.polylinesLayer.eachLayer((layer) => {
      if (layer instanceof L.Polyline) {
        layer.setStyle({ opacity: opacity });
      }
    });
  }

}
