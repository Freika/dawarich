import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import "leaflet.heat";
import consumer from "../channels/consumer";  // Add this import

import { createMarkersArray } from "../maps/markers";

import { createPolylinesLayer } from "../maps/polylines";
import { updatePolylinesOpacity } from "../maps/polylines";

import { fetchAndDrawAreas } from "../maps/areas";
import { handleAreaCreated } from "../maps/areas";

import { showFlashMessage } from "../maps/helpers";
import { formatDate } from "../maps/helpers";

import { osmMapLayer } from "../maps/layers";
import { osmHotMapLayer } from "../maps/layers";
import { OPNVMapLayer } from "../maps/layers";
import { openTopoMapLayer } from "../maps/layers";
import { cyclOsmMapLayer } from "../maps/layers";
import { esriWorldStreetMapLayer } from "../maps/layers";
import { esriWorldTopoMapLayer } from "../maps/layers";
import { esriWorldImageryMapLayer } from "../maps/layers";
import { esriWorldGrayCanvasMapLayer } from "../maps/layers";
import { countryCodesMap } from "../maps/country_codes";

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
    this.pointsRenderingMode = this.userSettings.points_rendering_mode || "raw";
    this.countryCodesMap = countryCodesMap();

    this.center = this.markers[this.markers.length - 1] || [52.514568, 13.350111];

    this.map = L.map(this.containerTarget).setView([this.center[0], this.center[1]], 14);

    // Set the maximum bounds to prevent infinite scroll
    var southWest = L.latLng(-90, -180);
    var northEast = L.latLng(90, 180);
    var bounds = L.latLngBounds(southWest, northEast);

    this.map.setMaxBounds(bounds);

    this.markersArray = createMarkersArray(this.markers, this.userSettings);
    this.markersLayer = L.layerGroup(this.markersArray);
    this.heatmapMarkers = this.markersArray.map((element) => [element._latlng.lat, element._latlng.lng, 0.2]);

    this.polylinesLayer = createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity, this.userSettings);
    this.heatmapLayer = L.heatLayer(this.heatmapMarkers, { radius: 20 }).addTo(this.map);
    this.fogOverlay = L.layerGroup(); // Initialize fog layer
    this.areasLayer = L.layerGroup(); // Initialize areas layer
    this.setupScratchLayer(this.countryCodesMap);

    if (!this.settingsButtonAdded) {
      this.addSettingsButton();
    }

    const controlsLayer = {
      Points: this.markersLayer,
      Polylines: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      "Scratch map": this.scratchLayer,
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
    fetchAndDrawAreas(this.areasLayer, this.apiKey);

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

    this.setupSubscription();  // Add this line
  }

  disconnect() {
    this.map.remove();
  }

  setupSubscription() {
    consumer.subscriptions.create("PointsChannel", {
      received: (data) => {
        // TODO:
        // Only append the point if its timestamp is within current
        // timespan
        this.appendPoint(data);
      }
    });
  }

  appendPoint(data) {
    // Parse the received point data
    const newPoint = data;

    // Add the new point to the markers array
    this.markers.push(newPoint);

    // Create a new marker for the point
    const markerOptions = {
      ...this.userSettings,  // Pass any relevant settings
      id: newPoint[6],       // Assuming index 6 contains the point ID
      timestamp: newPoint[4] // Assuming index 2 contains the timestamp
    };

    const newMarker = this.createMarker(newPoint, markerOptions);
    this.markersArray.push(newMarker);

    // Update the markers layer
    this.markersLayer.clearLayers();
    this.markersLayer.addLayer(L.layerGroup(this.markersArray));

    // Update heatmap
    this.heatmapMarkers.push([newPoint[0], newPoint[1], 0.2]);
    this.heatmapLayer.setLatLngs(this.heatmapMarkers);

    // Update polylines
    this.polylinesLayer.clearLayers();
    this.polylinesLayer = createPolylinesLayer(
      this.markers,
      this.map,
      this.timezone,
      this.routeOpacity,
      this.userSettings
    );

    // Pan map to new location
    this.map.setView([newPoint[0], newPoint[1]], 14);

    // Update fog of war if enabled
    if (this.map.hasLayer(this.fogOverlay)) {
      this.updateFog(this.markers, this.clearFogRadius);
    }

    // Update the last marker
    this.map.eachLayer((layer) => {
      if (layer instanceof L.Marker && !layer._popup) {
        this.map.removeLayer(layer);
      }
    });

    this.addLastMarker(this.map, this.markers);

    this.openNewMarkerPopup(newPoint);
  }

  openNewMarkerPopup(point) {
    // Create a temporary marker just for displaying the timestamp
    const timestamp = formatDate(point[4], this.timezone);

    const tempMarker = L.marker([point[0], point[1]]);
    const popupContent = `
      <div>
        <p><strong>${timestamp}</strong></p>
      </div>
    `;

    tempMarker
      .bindPopup(popupContent)
      .addTo(this.map)
      .openPopup();

      // Remove the temporary marker after 5 seconds
    setTimeout(() => {
      this.map.removeLayer(tempMarker);
    }, 300);
  }


  createMarker(point, options) {
    const marker = L.marker([point[0], point[1]]);

    // Add popup content based on point data
    const popupContent = `
      <div>
        <p>Time: ${new Date(point[2]).toLocaleString()}</p>
        ${point[3] ? `<p>Address: ${point[3]}</p>` : ''}
        ${point[7] ? `<p>Country: ${point[7]}</p>` : ''}
        <a href="#" class="delete-point" data-id="${point[6]}">Delete</a>
      </div>
    `;

    marker.bindPopup(popupContent);
    return marker;
  }

  async setupScratchLayer(countryCodesMap) {
    this.scratchLayer = L.geoJSON(null, {
      style: {
        fillColor: '#FFD700',
        fillOpacity: 0.3,
        color: '#FFA500',
        weight: 1
      }
    })

    try {
      // Up-to-date version can be found on Github:
      // https://raw.githubusercontent.com/datasets/geo-countries/master/data/countries.geojson
      const response = await fetch('/api/v1/countries/borders.json', {
        headers: {
          'Accept': 'application/geo+json,application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const worldData = await response.json();

      const visitedCountries = this.getVisitedCountries(countryCodesMap)
      const filteredFeatures = worldData.features.filter(feature =>
        visitedCountries.includes(feature.properties.ISO_A2)
      )

      this.scratchLayer.addData({
        type: 'FeatureCollection',
        features: filteredFeatures
      })
    } catch (error) {
      console.error('Error loading GeoJSON:', error);
    }
  }


  getVisitedCountries(countryCodesMap) {
    if (!this.markers) return [];

    return [...new Set(
      this.markers
        .filter(marker => marker[7]) // Ensure country exists
        .map(marker => {
          // Convert country name to ISO code, or return the original if not found
          return countryCodesMap[marker[7]] || marker[7];
        })
    )];
  }

  // Optional: Add methods to handle user interactions
  toggleScratchLayer() {
    if (this.map.hasLayer(this.scratchLayer)) {
      this.map.removeLayer(this.scratchLayer)
    } else {
      this.scratchLayer.addTo(this.map)
    }
  }

  baseMaps() {
    let selectedLayerName = this.userSettings.preferred_map_layer || "OpenStreetMap";

    return {
      OpenStreetMap: osmMapLayer(this.map, selectedLayerName),
      "OpenStreetMap.HOT": osmHotMapLayer(this.map, selectedLayerName),
      OPNV: OPNVMapLayer(this.map, selectedLayerName),
      openTopo: openTopoMapLayer(this.map, selectedLayerName),
      cyclOsm: cyclOsmMapLayer(this.map, selectedLayerName),
      esriWorldStreet: esriWorldStreetMapLayer(this.map, selectedLayerName),
      esriWorldTopo: esriWorldTopoMapLayer(this.map, selectedLayerName),
      esriWorldImagery: esriWorldImageryMapLayer(this.map, selectedLayerName),
      esriWorldGrayCanvas: esriWorldGrayCanvasMapLayer(this.map, selectedLayerName)
    };
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
        showFlashMessage('notice', `Preferred map layer updated to: ${selectedLayerName}`);
      } else {
        showFlashMessage('error', data.message);
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
        handleAreaCreated(this.areasLayer, layer, this.apiKey);
      }

      this.drawnItems.addLayer(layer);
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


          <label for="points_rendering_mode">
            Points rendering mode
            <label for="points_rendering_mode_info" class="btn-xs join-item inline">?</label>
          </label>
          <label for="raw">
            <input type="radio" id="raw" name="points_rendering_mode" class='w-4' style="width: 20px;" value="raw" ${this.pointsRenderingModeChecked('raw')} />
            Raw
          </label>

          <label for="simplified">
            <input type="radio" id="simplified" name="points_rendering_mode" class='w-4' style="width: 20px;" value="simplified" ${this.pointsRenderingModeChecked('simplified')}/>
            Simplified
          </label>

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

  pointsRenderingModeChecked(value) {
    if (value === this.pointsRenderingMode) {
      return 'checked';
    } else {
      return '';
    }
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
          points_rendering_mode: event.target.points_rendering_mode.value
        },
      }),
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.status === 'success') {
          showFlashMessage('notice', data.message);
          this.updateMapWithNewSettings(data.settings);
        } else {
          showFlashMessage('error', data.message);
        }
      });
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
    this.markersLayer = preserveLayers.Points       || L.layerGroup(createMarkersArray(this.markers, newSettings));
    this.polylinesLayer = preserveLayers.Polylines  || createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity, this.userSettings);
    this.heatmapLayer = preserveLayers.Heatmap      || L.heatLayer(this.markers.map((element) => [element[0], element[1], 0.2]), { radius: 20 });
    this.fogOverlay = preserveLayers["Fog of War"]  || L.layerGroup();
    this.areasLayer = preserveLayers.Areas          || L.layerGroup();

    // Redraw areas
    fetchAndDrawAreas(this.areasLayer, this.apiKey);

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
    updatePolylinesOpacity(this.polylinesLayer, this.routeOpacity);

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
}
