import { Controller } from "@hotwired/stimulus";
import maplibregl from 'maplibre-gl';
import BaseController from "./base_controller";
import {
  addPolylinesLayer,
  setupPolylineInteractions,
  updatePolylinesOpacity,
  updatePolylinesColors,
  removePolylinesLayer
} from "../maplibre/polylines";
import {
  createCompactLayerControl,
  addLayerKeyboardShortcuts
} from "../maplibre/layer_control";

export default class extends BaseController {
  static targets = ["container"];

  // Layer references
  polylinesLayerInfo = null;
  layerControl = null;
  keyboardShortcutsCleanup = null;

  connect() {
    super.connect();
    console.log("MapLibre controller connected");

    // Parse data attributes (same as maps controller)
    this.apiKey = this.element.dataset.api_key;
    this.selfHosted = this.element.dataset.self_hosted;
    this.userTheme = this.element.dataset.user_theme || 'dark';

    try {
      this.markers = this.element.dataset.coordinates ? JSON.parse(this.element.dataset.coordinates) : [];
    } catch (error) {
      console.error('Error parsing coordinates data:', error);
      this.markers = [];
    }

    try {
      this.userSettings = this.element.dataset.user_settings ? JSON.parse(this.element.dataset.user_settings) : {};
    } catch (error) {
      console.error('Error parsing user_settings data:', error);
      this.userSettings = {};
    }

    try {
      this.features = this.element.dataset.features ? JSON.parse(this.element.dataset.features) : {};
    } catch (error) {
      console.error('Error parsing features data:', error);
      this.features = {};
    }

    this.distanceUnit = this.userSettings.maps?.distance_unit || "km";
    this.timezone = this.element.dataset.timezone;

    // Initialize MapLibre map
    this.initializeMap();
  }

  disconnect() {
    console.log("MapLibre controller disconnecting");

    // Clean up keyboard shortcuts
    if (this.keyboardShortcutsCleanup) {
      this.keyboardShortcutsCleanup();
      this.keyboardShortcutsCleanup = null;
    }

    // Clean up layer control
    if (this.layerControl) {
      this.layerControl.remove();
      this.layerControl = null;
    }

    // Clean up map resources
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }

  initializeMap() {
    console.log("Initializing MapLibre map");

    // Determine initial center and zoom
    let center = [0, 0];
    let zoom = 2;

    if (this.markers.length > 0) {
      // Use first marker as center
      const firstMarker = this.markers[0];
      center = [firstMarker[1], firstMarker[0]]; // MapLibre uses [lng, lat]
      zoom = 13;
    }

    // Get preferred map style
    const preferredStyle = this.getPreferredStyle();

    // Initialize map
    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: preferredStyle,
      center: center,
      zoom: zoom,
      attributionControl: true
    });

    // Add navigation controls
    this.map.addControl(new maplibregl.NavigationControl(), 'top-left');

    // Add scale control
    const scaleUnit = this.distanceUnit === 'mi' ? 'imperial' : 'metric';
    this.map.addControl(new maplibregl.ScaleControl({ unit: scaleUnit }), 'bottom-left');

    // Wait for map to load before adding data
    this.map.on('load', () => {
      console.log("MapLibre map loaded");
      this.onMapLoaded();
    });

    // Add geolocate control
    this.map.addControl(
      new maplibregl.GeolocateControl({
        positionOptions: {
          enableHighAccuracy: true
        },
        trackUserLocation: true
      }),
      'top-left'
    );

    // Store map reference globally for other controllers
    window.maplibreController = this;

    // Add fullscreen control
    this.map.addControl(new maplibregl.FullscreenControl(), 'top-left');

    console.log(`MapLibre initialized with ${this.markers.length} markers`);
  }

  onMapLoaded() {
    console.log("MapLibre map ready, adding layers");

    // Add layers if data available
    if (this.markers.length > 0) {
      // Add polylines first (they go underneath points)
      this.addPolylines();

      // Then add point markers
      this.addMarkers();

      // Fit bounds to show all data
      this.fitBoundsToMarkers();

      // Add layer control UI
      this.addLayerControl();
    }
  }

  addLayerControl() {
    console.log('Adding layer control');

    // Create compact layer control with toggle button
    this.layerControl = createCompactLayerControl(this.map, {
      userTheme: this.userTheme,
      position: 'top-right'
    });

    // Add keyboard shortcuts (P = points, R = routes)
    this.keyboardShortcutsCleanup = addLayerKeyboardShortcuts(this.layerControl);

    console.log('Layer control added (keyboard shortcuts: P = Points, R = Routes)');
  }

  addPolylines() {
    if (this.markers.length < 2) {
      console.log('Not enough markers for polylines');
      return;
    }

    console.log('Adding polylines layer');

    // Add polylines layer
    this.polylinesLayerInfo = addPolylinesLayer(
      this.map,
      this.markers,
      this.userSettings,
      this.distanceUnit
    );

    // Setup interactions (hover, click)
    if (this.polylinesLayerInfo) {
      setupPolylineInteractions(
        this.map,
        this.userSettings,
        this.distanceUnit
      );

      console.log('Polylines layer and interactions added');
    }
  }

  addMarkers() {
    // Convert markers data to GeoJSON
    const geojsonData = {
      type: 'FeatureCollection',
      features: this.markers.map((marker, index) => ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [marker[1], marker[0]] // [lng, lat]
        },
        properties: {
          id: marker[6] || index,
          battery: marker[2],
          altitude: marker[3],
          timestamp: marker[4],
          velocity: marker[5],
          country: marker[7]
        }
      }))
    };

    // Add source
    this.map.addSource('points', {
      type: 'geojson',
      data: geojsonData
    });

    // Add layer for points
    this.map.addLayer({
      id: 'points-layer',
      type: 'circle',
      source: 'points',
      paint: {
        'circle-radius': 6,
        'circle-color': '#3388ff',
        'circle-opacity': 0.8,
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff'
      }
    });

    // Add click handler for popups
    this.map.on('click', 'points-layer', (e) => {
      const coordinates = e.features[0].geometry.coordinates.slice();
      const properties = e.features[0].properties;

      // Format popup content
      const popupContent = this.formatPopupContent(properties);

      new maplibregl.Popup()
        .setLngLat(coordinates)
        .setHTML(popupContent)
        .addTo(this.map);
    });

    // Change cursor on hover
    this.map.on('mouseenter', 'points-layer', () => {
      this.map.getCanvas().style.cursor = 'pointer';
    });

    this.map.on('mouseleave', 'points-layer', () => {
      this.map.getCanvas().style.cursor = '';
    });

    console.log(`Added ${this.markers.length} markers to MapLibre map`);
  }

  formatPopupContent(properties) {
    const timestamp = properties.timestamp ? new Date(properties.timestamp * 1000).toLocaleString() : 'N/A';
    const battery = properties.battery !== null ? `${properties.battery}%` : 'N/A';
    const altitude = properties.altitude !== null ? `${properties.altitude}m` : 'N/A';
    const velocity = properties.velocity !== null ? `${properties.velocity} km/h` : 'N/A';

    return `
      <div style="padding: 8px;">
        <p><strong>Time:</strong> ${timestamp}</p>
        <p><strong>Battery:</strong> ${battery}</p>
        <p><strong>Altitude:</strong> ${altitude}</p>
        <p><strong>Speed:</strong> ${velocity}</p>
        ${properties.country ? `<p><strong>Country:</strong> ${properties.country}</p>` : ''}
      </div>
    `;
  }

  fitBoundsToMarkers() {
    if (this.markers.length === 0) return;

    // Calculate bounds
    const bounds = new maplibregl.LngLatBounds();

    this.markers.forEach(marker => {
      bounds.extend([marker[1], marker[0]]); // [lng, lat]
    });

    // Fit map to bounds with padding
    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15
    });
  }

  getPreferredStyle() {
    // Check if user has a preferred style from settings
    const preferredLayer = this.userSettings.preferred_map_layer;

    // Define available styles
    const styles = {
      'OSM': this.getOSMStyle(),
      'Streets': this.getStreetsStyle(),
      'Satellite': this.getSatelliteStyle(),
      'Dark': this.getDarkStyle(),
      'Light': this.getLightStyle()
    };

    // Return preferred style or default based on theme
    if (preferredLayer && styles[preferredLayer]) {
      return styles[preferredLayer];
    }

    // Default to theme-based style
    return this.userTheme === 'dark' ? this.getDarkStyle() : this.getLightStyle();
  }

  getOSMStyle() {
    // OpenStreetMap style using raster tiles
    return {
      version: 8,
      sources: {
        'raster-tiles': {
          type: 'raster',
          tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
          tileSize: 256,
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        }
      },
      layers: [{
        id: 'simple-tiles',
        type: 'raster',
        source: 'raster-tiles',
        minzoom: 0,
        maxzoom: 22
      }]
    };
  }

  getStreetsStyle() {
    // Use OpenMapTiles schema with Stadia maps
    return 'https://tiles.stadiamaps.com/styles/alidade_smooth.json';
  }

  getSatelliteStyle() {
    // Satellite imagery style
    return {
      version: 8,
      sources: {
        'satellite': {
          type: 'raster',
          tiles: [
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
          ],
          tileSize: 256,
          attribution: 'Tiles &copy; Esri'
        }
      },
      layers: [{
        id: 'satellite',
        type: 'raster',
        source: 'satellite',
        minzoom: 0,
        maxzoom: 22
      }]
    };
  }

  getDarkStyle() {
    // Dark theme style
    return {
      version: 8,
      sources: {
        'raster-tiles': {
          type: 'raster',
          tiles: ['https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}.png'],
          tileSize: 256,
          attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>'
        }
      },
      layers: [{
        id: 'dark-tiles',
        type: 'raster',
        source: 'raster-tiles',
        minzoom: 0,
        maxzoom: 22
      }]
    };
  }

  getLightStyle() {
    // Light theme style (same as OSM for now)
    return this.getOSMStyle();
  }
}
