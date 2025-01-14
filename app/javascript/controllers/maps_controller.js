import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import "leaflet.heat";
import consumer from "../channels/consumer";

import { createMarkersArray } from "../maps/markers";

import {
  createPolylinesLayer,
  updatePolylinesOpacity,
  updatePolylinesColors,
  calculateSpeed,
  getSpeedColor
} from "../maps/polylines";

import { fetchAndDrawAreas } from "../maps/areas";
import { handleAreaCreated } from "../maps/areas";

import { showFlashMessage } from "../maps/helpers";
import { fetchAndDisplayPhotos } from '../maps/helpers';

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

function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

export default class extends Controller {
  static targets = ["container"];

  settingsButtonAdded = false;
  layerControl = null;
  visitedCitiesCache = new Map();
  trackedMonthsCache = null;

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
    this.liveMapEnabled = this.userSettings.live_map_enabled || false;
    this.countryCodesMap = countryCodesMap();
    this.speedColoredPolylines = this.userSettings.speed_colored_routes || false;

    this.center = this.markers[this.markers.length - 1] || [52.514568, 13.350111];

    this.map = L.map(this.containerTarget).setView([this.center[0], this.center[1]], 14);

    // Set the maximum bounds to prevent infinite scroll
    var southWest = L.latLng(-120, -210);
    var northEast = L.latLng(120, 210);
    var bounds = L.latLngBounds(southWest, northEast);

    this.map.setMaxBounds(bounds);

    this.markersArray = createMarkersArray(this.markers, this.userSettings, this.apiKey);
    this.markersLayer = L.layerGroup(this.markersArray);

    // Filter out the polyline before creating heatmap markers
    const markerElements = this.markersArray.filter(element => element instanceof L.Marker);
    this.heatmapMarkers = markerElements.map((element) => [
      element._latlng.lat,
      element._latlng.lng,
      0.2
    ]);

    this.polylinesLayer = createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity, this.userSettings, this.distanceUnit);
    this.heatmapLayer = L.heatLayer(this.heatmapMarkers, { radius: 20 }).addTo(this.map);
    this.fogOverlay = L.layerGroup(); // Initialize fog layer
    this.areasLayer = L.layerGroup(); // Initialize areas layer
    this.photoMarkers = L.layerGroup();

    this.setupScratchLayer(this.countryCodesMap);

    if (!this.settingsButtonAdded) {
      this.addSettingsButton();
    }

    const controlsLayer = {
      Points: this.markersLayer,
      Routes: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      "Scratch map": this.scratchLayer,
      Areas: this.areasLayer,
      Photos: this.photoMarkers
    };

    // Add this new custom control BEFORE the scale control
    const TestControl = L.Control.extend({
      onAdd: (map) => {
        const div = L.DomUtil.create('div', 'leaflet-control');
        const distance = this.element.dataset.distance || '0';
        const pointsNumber = this.element.dataset.points_number || '0';
        const unit = this.distanceUnit === 'mi' ? 'mi' : 'km';
        div.innerHTML = `${distance} ${unit} | ${pointsNumber} points`;
        div.style.backgroundColor = 'white';
        div.style.padding = '0 5px';
        div.style.marginRight = '5px';
        div.style.display = 'inline-block';
        return div;
      }
    });

    // Add the test control first
    new TestControl({ position: 'bottomright' }).addTo(this.map);

    // Then add scale control
    L.control.scale({
      position: 'bottomright',
      imperial: this.distanceUnit === 'mi',
      metric: this.distanceUnit === 'km',
      maxWidth: 120
    }).addTo(this.map)

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
    this.map.on('overlayadd', async (e) => {
      if (e.name === 'Areas') {
        this.map.addControl(this.drawControl);
      }
      if (e.name === 'Photos') {
        if (
          (!this.userSettings.immich_url || !this.userSettings.immich_api_key) &&
          (!this.userSettings.photoprism_url || !this.userSettings.photoprism_api_key)
        ) {
          showFlashMessage(
            'error',
            'Photos integration is not configured. Please check your integrations settings.'
          );
          return;
        }

        const urlParams = new URLSearchParams(window.location.search);
        const startDate = urlParams.get('start_at')?.split('T')[0] || new Date().toISOString().split('T')[0];
        const endDate = urlParams.get('end_at')?.split('T')[0] || new Date().toISOString().split('T')[0];
        await fetchAndDisplayPhotos({
          map: this.map,
          photoMarkers: this.photoMarkers,
          apiKey: this.apiKey,
          startDate: startDate,
          endDate: endDate,
          userSettings: this.userSettings
        });
      }
    });

    this.map.on('overlayremove', (e) => {
      if (e.name === 'Areas') {
        this.map.removeControl(this.drawControl);
      }
    });

    if (this.liveMapEnabled) {
      this.setupSubscription();
    }

    // Add the toggle panel button
    this.addTogglePanelButton();

    // Check if we should open the panel based on localStorage or URL params
    const urlParams = new URLSearchParams(window.location.search);
    const isPanelOpen = localStorage.getItem('mapPanelOpen') === 'true';
    const hasDateParams = urlParams.has('start_at') && urlParams.has('end_at');

    // Always create the panel first
    this.toggleRightPanel();

    // Then hide it if it shouldn't be open
    if (!isPanelOpen && !hasDateParams) {
      const panel = document.querySelector('.leaflet-right-panel');
      if (panel) {
        panel.style.display = 'none';
        localStorage.setItem('mapPanelOpen', 'false');
      }
    }
  }

  disconnect() {
    if (this.handleDeleteClick) {
      document.removeEventListener('click', this.handleDeleteClick);
    }
    // Store panel state before disconnecting
    if (this.rightPanel) {
      const finalState = document.querySelector('.leaflet-right-panel').style.display !== 'none' ? 'true' : 'false';
      localStorage.setItem('mapPanelOpen', finalState);
    }
    this.map.remove();
  }

  setupSubscription() {
    consumer.subscriptions.create("PointsChannel", {
      received: (data) => {
        // TODO:
        // Only append the point if its timestamp is within current
        // timespan
        if (this.map && this.map._loaded) {
          this.appendPoint(data);
        }
      }
    });
  }

  appendPoint(data) {
    // Parse the received point data
    const newPoint = data;

    // Add the new point to the markers array
    this.markers.push(newPoint);

    const newMarker = L.marker([newPoint[0], newPoint[1]])
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
      this.userSettings,
      this.distanceUnit
    );

    // Pan map to new location
    this.map.setView([newPoint[0], newPoint[1]], 16);

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
    // Create the handler only once and store it as an instance property
    if (!this.handleDeleteClick) {
      this.handleDeleteClick = (event) => {
        if (event.target && event.target.classList.contains('delete-point')) {
          event.preventDefault();
          const pointId = event.target.getAttribute('data-id');

          if (confirm('Are you sure you want to delete this point?')) {
            this.deletePoint(pointId, this.apiKey);
          }
        }
      };

      // Add the listener only if it hasn't been added before
      document.addEventListener('click', this.handleDeleteClick);
    }

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
      // Remove the marker and update all layers
      this.removeMarker(id);
      let wasPolyLayerVisible = false;
      // Explicitly remove old polylines layer from map
      if (this.polylinesLayer) {
        if (this.map.hasLayer(this.polylinesLayer)) {
          wasPolyLayerVisible = true;
        }
        this.map.removeLayer(this.polylinesLayer);

      }

      // Create new polylines layer
      this.polylinesLayer = createPolylinesLayer(
        this.markers,
        this.map,
        this.timezone,
        this.routeOpacity,
        this.userSettings,
        this.distanceUnit
      );
      if (wasPolyLayerVisible) {
        // Add new polylines layer to map and to layer control
        this.polylinesLayer.addTo(this.map);
      } else {
        this.map.removeLayer(this.polylinesLayer);
      }
      // Update the layer control
      if (this.layerControl) {
        this.map.removeControl(this.layerControl);
        const controlsLayer = {
          Points: this.markersLayer,
          Routes: this.polylinesLayer,
          Heatmap: this.heatmapLayer,
          "Fog of War": this.fogOverlay,
          "Scratch map": this.scratchLayer,
          Areas: this.areasLayer,
          Photos: this.photoMarkers
        };
        this.layerControl = L.control.layers(this.baseMaps(), controlsLayer).addTo(this.map);
      }

      // Update heatmap
      this.heatmapLayer.setLatLngs(this.markers.map(marker => [marker[0], marker[1], 0.2]));

      // Update fog if enabled
      if (this.map.hasLayer(this.fogOverlay)) {
        this.updateFog(this.markers, this.clearFogRadius);
      }
    })
    .catch(error => {
      console.error('There was a problem with the delete request:', error);
      showFlashMessage('error', 'Failed to delete point');
    });
  }

  removeMarker(id) {
    const numericId = parseInt(id);

    const markerIndex = this.markersArray.findIndex(marker =>
      marker.getPopup().getContent().includes(`data-id="${id}"`)
    );

    if (markerIndex !== -1) {
      this.markersArray[markerIndex].remove();
      this.markersArray.splice(markerIndex, 1);
      this.markersLayer.clearLayers();
      this.markersLayer.addLayer(L.layerGroup(this.markersArray));

      this.markers = this.markers.filter(marker => {
        const markerId = parseInt(marker[6]);
        return markerId !== numericId;
      });
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

          <label for="live_map_enabled">
            Live Map
            <label for="live_map_enabled_info" class="btn-xs join-item inline">?</label>
            <input type="checkbox" id="live_map_enabled" name="live_map_enabled" class='w-4' style="width: 20px;" value="false" ${this.liveMapEnabledChecked(true)} />
          </label>

          <label for="speed_colored_routes">
            Speed-colored routes
            <label for="speed_colored_routes_info" class="btn-xs join-item inline">?</label>
            <input type="checkbox" id="speed_colored_routes" name="speed_colored_routes" class='w-4' style="width: 20px;" ${this.speedColoredRoutesChecked()} />
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

  liveMapEnabledChecked(value) {
    if (value === this.liveMapEnabled) {
      return 'checked';
    } else {
      return '';
    }
  }

  speedColoredRoutesChecked() {
    return this.userSettings.speed_colored_routes ? 'checked' : '';
  }

  updateSettings(event) {
    event.preventDefault();
    console.log('Form submitted');

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
          points_rendering_mode: event.target.points_rendering_mode.value,
          live_map_enabled: event.target.live_map_enabled.checked,
          speed_colored_routes: event.target.speed_colored_routes.checked
        },
      }),
    })
      .then((response) => response.json())
      .then((data) => {
        console.log('Settings update response:', data);
        if (data.status === 'success') {
          showFlashMessage('notice', data.message);
          this.updateMapWithNewSettings(data.settings);

          if (data.settings.live_map_enabled) {
            this.setupSubscription();
          }
        } else {
          showFlashMessage('error', data.message);
        }
      })
      .catch(error => {
        console.error('Settings update error:', error);
        showFlashMessage('error', 'Failed to update settings');
      });
  }

  updateMapWithNewSettings(newSettings) {
    console.log('Updating map settings:', {
      newSettings,
      currentSettings: this.userSettings,
      hasPolylines: !!this.polylinesLayer,
      isVisible: this.polylinesLayer && this.map.hasLayer(this.polylinesLayer)
    });

    // Show loading indicator
    const loadingDiv = document.createElement('div');
    loadingDiv.className = 'map-loading-overlay';
    loadingDiv.innerHTML = '<div class="loading loading-lg">Updating map...</div>';
    document.body.appendChild(loadingDiv);

    // Debounce the heavy operations
    const updateLayers = debounce(() => {
      try {
        // Check if speed_colored_routes setting has changed
        if (newSettings.speed_colored_routes !== this.userSettings.speed_colored_routes) {
          if (this.polylinesLayer) {
            updatePolylinesColors(
              this.polylinesLayer,
              newSettings.speed_colored_routes
            );
          }
        }

        // Update opacity if changed
        if (newSettings.route_opacity !== this.userSettings.route_opacity) {
          const newOpacity = parseFloat(newSettings.route_opacity) || 0.6;
          if (this.polylinesLayer) {
            updatePolylinesOpacity(this.polylinesLayer, newOpacity);
          }
        }

        // Update the local settings
        this.userSettings = { ...this.userSettings, ...newSettings };
        this.routeOpacity = parseFloat(newSettings.route_opacity) || 0.6;
        this.clearFogRadius = parseInt(newSettings.fog_of_war_meters) || 50;

        // Update layer control
        this.map.removeControl(this.layerControl);
        const controlsLayer = {
          Points: this.markersLayer,
          Routes: this.polylinesLayer,
          Heatmap: this.heatmapLayer,
          "Fog of War": this.fogOverlay,
          "Scratch map": this.scratchLayer,
          Areas: this.areasLayer,
          Photos: this.photoMarkers
        };
        this.layerControl = L.control.layers(this.baseMaps(), controlsLayer).addTo(this.map);

      } catch (error) {
        console.error('Error updating map settings:', error);
        console.error(error.stack);
      } finally {
        // Remove loading indicator after all updates are complete
        setTimeout(() => {
          document.body.removeChild(loadingDiv);
        }, 500); // Give a small delay to ensure all batches are processed
      }
    }, 250);

    updateLayers();
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
      Routes: this.polylinesLayer,
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
    console.log('Applying layer states:', states);

    const layerControl = {
      Points: this.markersLayer,
      Routes: this.polylinesLayer,
      Heatmap: this.heatmapLayer,
      "Fog of War": this.fogOverlay,
      Areas: this.areasLayer,
    };

    for (const [name, isVisible] of Object.entries(states)) {
      const layer = layerControl[name];
      console.log(`Processing layer ${name}:`, { layer, isVisible });

      if (layer) {
        if (isVisible && !this.map.hasLayer(layer)) {
          console.log(`Adding layer ${name} to map`);
          this.map.addLayer(layer);
        } else if (!isVisible && this.map.hasLayer(layer)) {
          console.log(`Removing layer ${name} from map`);
          this.map.removeLayer(layer);
        }
      }
    }

    // Ensure the layer control reflects the current state
    this.map.removeControl(this.layerControl);
    this.layerControl = L.control.layers(this.baseMaps(), layerControl).addTo(this.map);
  }

  createPhotoMarker(photo) {
    if (!photo.exifInfo?.latitude || !photo.exifInfo?.longitude) return;

    const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.apiKey}&source=${photo.source}`;

    const icon = L.divIcon({
      className: 'photo-marker',
      html: `<img src="${thumbnailUrl}" style="width: 48px; height: 48px;">`,
      iconSize: [48, 48]
    });

    const marker = L.marker(
      [photo.exifInfo.latitude, photo.exifInfo.longitude],
      { icon }
    );

    const startOfDay = new Date(photo.localDateTime);
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date(photo.localDateTime);
    endOfDay.setHours(23, 59, 59, 999);

    const queryParams = {
      takenAfter: startOfDay.toISOString(),
      takenBefore: endOfDay.toISOString()
    };
    const encodedQuery = encodeURIComponent(JSON.stringify(queryParams));
    const immich_photo_link = `${this.userSettings.immich_url}/search?query=${encodedQuery}`;
    const popupContent = `
      <div class="max-w-xs">
        <a href="${immich_photo_link}" target="_blank" onmouseover="this.firstElementChild.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.3)';"
   onmouseout="this.firstElementChild.style.boxShadow = '';">
          <img src="${thumbnailUrl}"
              class="w-8 h-8 mb-2 rounded"
              style="transition: box-shadow 0.3s ease;"
              alt="${photo.originalFileName}">
        </a>
        <h3 class="font-bold">${photo.originalFileName}</h3>
        <p>Taken: ${new Date(photo.localDateTime).toLocaleString()}</p>
        <p>Location: ${photo.exifInfo.city}, ${photo.exifInfo.state}, ${photo.exifInfo.country}</p>
        ${photo.type === 'video' ? '🎥 Video' : '📷 Photo'}
      </div>
    `;
    marker.bindPopup(popupContent, { autoClose: false });

    this.photoMarkers.addLayer(marker);
  }

  addTogglePanelButton() {
    const TogglePanelControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'toggle-panel-button');
        button.innerHTML = '📅';

        button.style.backgroundColor = 'white';
        button.style.width = '48px';
        button.style.height = '48px';
        button.style.border = 'none';
        button.style.cursor = 'pointer';
        button.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';

        // Disable map interactions when clicking the button
        L.DomEvent.disableClickPropagation(button);

        // Toggle panel on button click
        L.DomEvent.on(button, 'click', () => {
          this.toggleRightPanel();
        });

        return button;
      }
    });

    // Add the control to the map
    this.map.addControl(new TogglePanelControl({ position: 'topright' }));
  }

  toggleRightPanel() {
    if (this.rightPanel) {
      const panel = document.querySelector('.leaflet-right-panel');
      if (panel) {
        if (panel.style.display === 'none') {
          panel.style.display = 'block';
          localStorage.setItem('mapPanelOpen', 'true');
        } else {
          panel.style.display = 'none';
          localStorage.setItem('mapPanelOpen', 'false');
        }
        return;
      }
    }

    this.rightPanel = L.control({ position: 'topright' });

    this.rightPanel.onAdd = () => {
      const div = L.DomUtil.create('div', 'leaflet-right-panel');
      const allMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

      // Get current date from URL query parameters
      const urlParams = new URLSearchParams(window.location.search);
      const startDate = urlParams.get('start_at');
      const currentYear = startDate
        ? new Date(startDate).getFullYear().toString()
        : new Date().getFullYear().toString();
      const currentMonth = startDate
        ? allMonths[new Date(startDate).getMonth()]
        : allMonths[new Date().getMonth()];

      // Initially create select with loading state and current year if available
      div.innerHTML = `
        <div class="panel-content">
          <div id='years-nav'>
            <div class="flex gap-2 mb-4">
              <select id="year-select" class="select select-bordered w-1/2 max-w-xs">
                ${currentYear
                  ? `<option value="${currentYear}" selected>${currentYear}</option>`
                  : '<option disabled selected>Loading years...</option>'}
              </select>
              <a href="${this.getWholeYearLink()}"
                 id="whole-year-link"
                 class="btn btn-default"
                 style="color: rgb(116 128 255) !important;">
                Whole year
              </a>
            </div>

            <div class='grid grid-cols-3 gap-3' id="months-grid">
              ${allMonths.map(month => `
                <a href="#"
                   class="btn btn-primary disabled ${month === currentMonth ? 'btn-active' : ''}"
                   data-month-name="${month}"
                   style="pointer-events: none; opacity: 0.6; color: rgb(116 128 255) !important;">
                   <span class="loading loading-dots loading-md"></span>
                </a>
              `).join('')}
            </div>
          </div>

        </div>
      `;

      this.fetchAndDisplayTrackedMonths(div, currentYear, currentMonth, allMonths);

      div.style.backgroundColor = 'white';
      div.style.padding = '10px';
      div.style.border = '1px solid #ccc';
      div.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';
      div.style.marginRight = '10px';
      div.style.marginTop = '10px';
      div.style.width = '300px';
      div.style.maxHeight = '80vh';
      div.style.overflowY = 'auto';

      L.DomEvent.disableClickPropagation(div);

      // Add container for visited cities
      div.innerHTML += `
        <div id="visited-cities-container" class="mt-4">
          <h3 class="text-lg font-bold mb-2">Visited cities</h3>
          <div id="visited-cities-list" class="space-y-2"
               style="max-height: 300px; overflow-y: auto; overflow-x: auto; padding-right: 10px;">
            <p class="text-gray-500">Loading visited places...</p>
          </div>
        </div>
      `;

      // Prevent map zoom when scrolling the cities list
      const citiesList = div.querySelector('#visited-cities-list');
      L.DomEvent.disableScrollPropagation(citiesList);

      // Fetch visited cities when panel is first created
      this.fetchAndDisplayVisitedCities();

      // Set initial display style based on localStorage
      const isPanelOpen = localStorage.getItem('mapPanelOpen') === 'true';
      div.style.display = isPanelOpen ? 'block' : 'none';

      return div;
    };

    this.map.addControl(this.rightPanel);
  }

  async fetchAndDisplayTrackedMonths(div, currentYear, currentMonth, allMonths) {
    try {
      let yearsData;

      // Check cache first
      if (this.trackedMonthsCache) {
        yearsData = this.trackedMonthsCache;
      } else {
        const response = await fetch(`/api/v1/points/tracked_months?api_key=${this.apiKey}`);
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        yearsData = await response.json();
        // Store in cache
        this.trackedMonthsCache = yearsData;
      }

      const yearSelect = document.getElementById('year-select');

      if (!Array.isArray(yearsData) || yearsData.length === 0) {
        yearSelect.innerHTML = '<option disabled selected>No data available</option>';
        return;
      }

      // Check if the current year exists in the API response
      const currentYearData = yearsData.find(yearData => yearData.year.toString() === currentYear);

      const options = yearsData
        .filter(yearData => yearData && yearData.year)
        .map(yearData => {
          const months = Array.isArray(yearData.months) ? yearData.months : [];
          const isCurrentYear = yearData.year.toString() === currentYear;
          return `
            <option value="${yearData.year}"
                    data-months='${JSON.stringify(months)}'
                    ${isCurrentYear ? 'selected' : ''}>
              ${yearData.year}
            </option>
          `;
        })
        .join('');

      yearSelect.innerHTML = `
        <option disabled>Select year</option>
        ${options}
      `;

      const updateMonthLinks = (selectedYear, availableMonths) => {
        // Get current date from URL parameters
        const urlParams = new URLSearchParams(window.location.search);
        const startDate = urlParams.get('start_at') ? new Date(urlParams.get('start_at')) : new Date();
        const endDate = urlParams.get('end_at') ? new Date(urlParams.get('end_at')) : new Date();

        allMonths.forEach((month, index) => {
          const monthLink = div.querySelector(`a[data-month-name="${month}"]`);
          if (!monthLink) return;

          // Update the content to show the month name instead of loading dots
          monthLink.innerHTML = month;

          // Check if this month falls within the selected date range
          const isSelected = startDate && endDate &&
            selectedYear === startDate.getFullYear().toString() && // Only check months for the currently selected year
            isMonthInRange(index, startDate, endDate, parseInt(selectedYear));

          if (availableMonths.includes(month)) {
            monthLink.classList.remove('disabled');
            monthLink.style.pointerEvents = 'auto';
            monthLink.style.opacity = '1';

            // Update the active state based on selection
            if (isSelected) {
              monthLink.classList.add('btn-active', 'btn-primary');
            } else {
              monthLink.classList.remove('btn-active', 'btn-primary');
            }

            const monthNum = (index + 1).toString().padStart(2, '0');
            const startDate = `${selectedYear}-${monthNum}-01T00:00`;
            const lastDay = new Date(selectedYear, index + 1, 0).getDate();
            const endDate = `${selectedYear}-${monthNum}-${lastDay}T23:59`;

            const href = `map?end_at=${encodeURIComponent(endDate)}&start_at=${encodeURIComponent(startDate)}`;
            monthLink.setAttribute('href', href);
          } else {
            monthLink.classList.add('disabled');
            monthLink.classList.remove('btn-active', 'btn-primary');
            monthLink.style.pointerEvents = 'none';
            monthLink.style.opacity = '0.6';
            monthLink.setAttribute('href', '#');
          }
        });
      };

      // Helper function to check if a month falls within a date range
      const isMonthInRange = (monthIndex, startDate, endDate, selectedYear) => {
        // Create date objects for the first and last day of the month in the selected year
        const monthStart = new Date(selectedYear, monthIndex, 1);
        const monthEnd = new Date(selectedYear, monthIndex + 1, 0);

        // Check if any part of the month overlaps with the selected date range
        return monthStart <= endDate && monthEnd >= startDate;
      };

      yearSelect.addEventListener('change', (event) => {
        const selectedOption = event.target.selectedOptions[0];
        const selectedYear = selectedOption.value;
        const availableMonths = JSON.parse(selectedOption.dataset.months || '[]');

        // Update whole year link with selected year
        const wholeYearLink = document.getElementById('whole-year-link');
        const startDate = `${selectedYear}-01-01T00:00`;
        const endDate = `${selectedYear}-12-31T23:59`;
        const href = `map?end_at=${encodeURIComponent(endDate)}&start_at=${encodeURIComponent(startDate)}`;
        wholeYearLink.setAttribute('href', href);

        updateMonthLinks(selectedYear, availableMonths);
      });

      // If we have a current year, set it and update month links
      if (currentYear && currentYearData) {
        yearSelect.value = currentYear;
        updateMonthLinks(currentYear, currentYearData.months);
      }
    } catch (error) {
      const yearSelect = document.getElementById('year-select');
      yearSelect.innerHTML = '<option disabled selected>Error loading years</option>';
      console.error('Error fetching tracked months:', error);
    }
  }

  chunk(array, size) {
    const chunked = [];
    for (let i = 0; i < array.length; i += size) {
      chunked.push(array.slice(i, i + size));
    }
    return chunked;
  }

  getWholeYearLink() {
    // First try to get year from URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    let year;

    if (urlParams.has('start_at')) {
      year = new Date(urlParams.get('start_at')).getFullYear();
    } else {
      // If no URL params, try to get year from start_at input
      const startAtInput = document.querySelector('input#start_at');
      if (startAtInput && startAtInput.value) {
        year = new Date(startAtInput.value).getFullYear();
      } else {
        // If no input value, use current year
        year = new Date().getFullYear();
      }
    }

    const startDate = `${year}-01-01T00:00`;
    const endDate = `${year}-12-31T23:59`;
    return `map?end_at=${encodeURIComponent(endDate)}&start_at=${encodeURIComponent(startDate)}`;
  }

  async fetchAndDisplayVisitedCities() {
    const urlParams = new URLSearchParams(window.location.search);
    const startAt = urlParams.get('start_at') || new Date().toISOString();
    const endAt = urlParams.get('end_at') || new Date().toISOString();

    // Create a cache key from the date range
    const cacheKey = `${startAt}-${endAt}`;

    // Check if we have cached data for this date range
    if (this.visitedCitiesCache.has(cacheKey)) {
      this.displayVisitedCities(this.visitedCitiesCache.get(cacheKey));
      return;
    }

    try {
      const response = await fetch(`/api/v1/countries/visited_cities?api_key=${this.apiKey}&start_at=${startAt}&end_at=${endAt}`, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }
      });

      if (!response.ok) {
        throw new Error('Network response was not ok');
      }

      const data = await response.json();

      // Cache the results
      this.visitedCitiesCache.set(cacheKey, data.data);

      this.displayVisitedCities(data.data);
    } catch (error) {
      console.error('Error fetching visited cities:', error);
      const container = document.getElementById('visited-cities-list');
      if (container) {
        container.innerHTML = '<p class="text-red-500">Error loading visited places</p>';
      }
    }
  }

  displayVisitedCities(citiesData) {
    const container = document.getElementById('visited-cities-list');
    if (!container) return;

    if (!citiesData || citiesData.length === 0) {
      container.innerHTML = '<p class="text-gray-500">No places visited during this period</p>';
      return;
    }

    const html = citiesData.map(country => `
      <div class="mb-4" style="min-width: min-content;">
        <h4 class="font-bold text-md">${country.country}</h4>
        <ul class="ml-4 space-y-1">
          ${country.cities.map(city => `
            <li class="text-sm whitespace-nowrap">
              ${city.city}
              <span class="text-gray-500">
                (${new Date(city.timestamp * 1000).toLocaleDateString()})
              </span>
            </li>
          `).join('')}
        </ul>
      </div>
    `).join('');

    container.innerHTML = html;
  }

  formatDuration(seconds) {
    const days = Math.floor(seconds / (24 * 60 * 60));
    const hours = Math.floor((seconds % (24 * 60 * 60)) / (60 * 60));

    if (days > 0) {
      return `${days}d ${hours}h`;
    }
    return `${hours}h`;
  }
}

