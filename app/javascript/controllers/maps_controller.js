import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import "leaflet.heat";
import "leaflet.control.layers.tree";
import consumer from "../channels/consumer";

import { createMarkersArray } from "../maps/markers";
import { LiveMapHandler } from "../maps/live_map_handler";

import {
  createPolylinesLayer,
  updatePolylinesOpacity,
  updatePolylinesColors,
  colorFormatEncode,
  colorFormatDecode,
  colorStopsFallback,
  reestablishPolylineEventHandlers,
  managePaneVisibility
} from "../maps/polylines";

import {
  createTracksLayer,
  updateTracksOpacity,
  toggleTracksVisibility,
  filterTracks,
  trackColorPalette,
  handleIncrementalTrackUpdate,
  addOrUpdateTrack,
  removeTrackById,
  isTrackInTimeRange
} from "../maps/tracks";

import { fetchAndDrawAreas, handleAreaCreated } from "../maps/areas";

import { showFlashMessage } from "../maps/helpers";
import { fetchAndDisplayPhotos } from "../maps/photos";
import { countryCodesMap } from "../maps/country_codes";
import { VisitsManager } from "../maps/visits";
import { ScratchLayer } from "../maps/scratch_layer";
import { LocationSearch } from "../maps/location_search";
import { PlacesManager } from "../maps/places";
import { PrivacyZoneManager } from "../maps/privacy_zones";

import "leaflet-draw";
import { initializeFogCanvas, drawFogCanvas, createFogOverlay } from "../maps/fog_of_war";
import BaseController from "./base_controller";
import { createAllMapLayers } from "../maps/layers";
import { applyThemeToControl, applyThemeToButton, applyThemeToPanel } from "../maps/theme_utils";
import {
  addTopRightButtons,
  setCreatePlaceButtonActive,
  setCreatePlaceButtonInactive
} from "../maps/map_controls";

export default class extends BaseController {
  static targets = ["container"];

  settingsButtonAdded = false;
  layerControl = null;
  visitedCitiesCache = new Map();
  trackedMonthsCache = null;
  tracksLayer = null;
  tracksVisible = false;
  tracksSubscription = null;

  async connect() {
    super.connect();
    console.log("Map controller connected");

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
      this.tracksData = this.element.dataset.tracks ? JSON.parse(this.element.dataset.tracks) : null;
    } catch (error) {
      console.error('Error parsing tracks data:', error);
      this.tracksData = null;
    }
    this.timezone = this.element.dataset.timezone;
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
    this.clearFogRadius = parseInt(this.userSettings.fog_of_war_meters) || 50;
    this.fogLineThreshold = parseInt(this.userSettings.fog_of_war_threshold) || 90;
    // Store route opacity as decimal (0-1) internally
    this.routeOpacity = parseFloat(this.userSettings.route_opacity) || 0.6;
    this.distanceUnit = this.userSettings.maps?.distance_unit || "km";
    this.pointsRenderingMode = this.userSettings.points_rendering_mode || "raw";
    this.liveMapEnabled = this.userSettings.live_map_enabled || false;
    this.countryCodesMap = countryCodesMap();
    this.speedColoredPolylines = this.userSettings.speed_colored_routes || false;
    this.speedColorScale = this.userSettings.speed_color_scale || colorFormatEncode(colorStopsFallback);

    // Flag to prevent saving layers during initialization/restoration
    this.isRestoringLayers = false;

    // Ensure we have valid markers array
    if (!Array.isArray(this.markers)) {
      console.warn('Markers is not an array, setting to empty array');
      this.markers = [];
    }

    // Set default center based on priority: Home place > last marker > Berlin
    let defaultCenter = [52.514568, 13.350111]; // Berlin as final fallback

    // Try to get Home place coordinates
    try {
      const homeCoords = this.element.dataset.home_coordinates ?
        JSON.parse(this.element.dataset.home_coordinates) : null;
      if (homeCoords && Array.isArray(homeCoords) && homeCoords.length === 2) {
        defaultCenter = homeCoords;
      }
    } catch (error) {
      console.warn('Error parsing home coordinates:', error);
    }

    // Use last marker if available, otherwise use default center (Home or Berlin)
    this.center = this.markers.length > 0 ? this.markers[this.markers.length - 1] : defaultCenter;

    this.map = L.map(this.containerTarget).setView([this.center[0], this.center[1]], 14);

    // Add scale control
    this.scaleControl = L.control.scale({
      position: 'bottomright',
      imperial: this.distanceUnit === 'mi',
      metric: this.distanceUnit === 'km',
      maxWidth: 120
    }).addTo(this.map);

    // Add stats control
    const StatsControl = L.Control.extend({
      options: {
        position: 'bottomright'
      },
      onAdd: (map) => {
        const div = L.DomUtil.create('div', 'leaflet-control-stats');
        let distance = parseInt(this.element.dataset.distance) || 0;
        const pointsNumber = this.element.dataset.points_number || '0';

        // Convert distance to miles if user prefers miles (assuming backend sends km)
        if (this.distanceUnit === 'mi') {
          distance = distance * 0.621371; // km to miles conversion
        }

        const unit = this.distanceUnit === 'km' ? 'km' : 'mi';
        div.innerHTML = `${distance} ${unit} | ${pointsNumber} points`;
        applyThemeToControl(div, this.userTheme, {
          padding: '0 5px',
          marginRight: '5px',
          display: 'inline-block'
        });
        return div;
      }
    });

    this.statsControl = new StatsControl().addTo(this.map);

    // Set the maximum bounds to prevent infinite scroll
    var southWest = L.latLng(-120, -210);
    var northEast = L.latLng(120, 210);
    var bounds = L.latLngBounds(southWest, northEast);

    this.map.setMaxBounds(bounds);

    // Initialize privacy zone manager
    this.privacyZoneManager = new PrivacyZoneManager(this.map, this.apiKey);

    // Load privacy zones and apply filtering BEFORE creating map layers
    await this.initializePrivacyZones();

    this.markersArray = createMarkersArray(this.markers, this.userSettings, this.apiKey);
    this.markersLayer = L.layerGroup(this.markersArray);
    this.heatmapMarkers = this.markersArray.map((element) => [element._latlng.lat, element._latlng.lng, 0.2]);

    this.polylinesLayer = createPolylinesLayer(this.markers, this.map, this.timezone, this.routeOpacity, this.userSettings, this.distanceUnit);
    this.heatmapLayer = L.heatLayer(this.heatmapMarkers, { radius: 20 }).addTo(this.map);

    // Initialize empty tracks layer for layer control (will be populated later)
    this.tracksLayer = L.layerGroup();

    // Create a proper Leaflet layer for fog
    this.fogOverlay = new (createFogOverlay())();

    // Create custom panes with proper z-index ordering
    // Leaflet default panes: tilePane=200, overlayPane=400, shadowPane=500, markerPane=600, tooltipPane=650, popupPane=700

    // Areas pane - below visits so they don't block interaction
    this.map.createPane('areasPane');
    this.map.getPane('areasPane').style.zIndex = 605; // Above markerPane but below visits
    this.map.getPane('areasPane').style.pointerEvents = 'none'; // Don't block clicks, let them pass through

    // Legacy visits pane for backward compatibility
    this.map.createPane('visitsPane');
    this.map.getPane('visitsPane').style.zIndex = 615;
    this.map.getPane('visitsPane').style.pointerEvents = 'auto';

    // Suggested visits pane - interactive layer
    this.map.createPane('suggestedVisitsPane');
    this.map.getPane('suggestedVisitsPane').style.zIndex = 610;
    this.map.getPane('suggestedVisitsPane').style.pointerEvents = 'auto';

    // Confirmed visits pane - on top of suggested, interactive
    this.map.createPane('confirmedVisitsPane');
    this.map.getPane('confirmedVisitsPane').style.zIndex = 620;
    this.map.getPane('confirmedVisitsPane').style.pointerEvents = 'auto';

    // Initialize areasLayer as a feature group and add it to the map immediately
    this.areasLayer = new L.FeatureGroup();
    this.photoMarkers = L.layerGroup();

    this.initializeScratchLayer();

    if (!this.settingsButtonAdded) {
      this.addSettingsButton();
    }

    // Add info toggle button
    this.addInfoToggleButton();

    // Initialize the visits manager
    this.visitsManager = new VisitsManager(this.map, this.apiKey, this.userTheme, this);

    // Expose visits manager globally for location search integration
    window.visitsManager = this.visitsManager;

    // Initialize the places manager
    this.placesManager = new PlacesManager(this.map, this.apiKey);
    this.placesManager.initialize();

    // Parse user tags for places layer control
    try {
      this.userTags = this.element.dataset.user_tags ? JSON.parse(this.element.dataset.user_tags) : [];
    } catch (error) {
      console.error('Error parsing user tags:', error);
      this.userTags = [];
    }

    // Expose maps controller globally for family integration
    window.mapsController = this;

    this.addEventListeners();
    this.setupSubscription();
    this.setupTracksSubscription();

    // Handle routes/tracks mode selection
    if (this.shouldShowTracksSelector()) {
      this.addRoutesTracksSelector();
    }
    this.switchRouteMode('routes', true);

    // Listen for Family Members layer becoming ready
    this.setupFamilyLayerListener();

    // Initialize tracks layer
    this.initializeTracksLayer();

    // Setup draw control
    this.initializeDrawControl();

    // Preload areas
    fetchAndDrawAreas(this.areasLayer, this.apiKey);

    // Add all top-right buttons in the correct order
    this.initializeTopRightButtons();

    // Initialize tree-based layer control (must be before initializeLayersFromSettings)
    this.layerControl = this.createTreeLayerControl();
    this.map.addControl(this.layerControl);

    // Initialize layers based on settings (must be after tree control creation)
    this.initializeLayersFromSettings();


    // Initialize Live Map Handler
    this.initializeLiveMapHandler();

    // Initialize Location Search
    this.initializeLocationSearch();
  }

  disconnect() {
    super.disconnect();
    this.removeEventListeners();

    if (this.tracksSubscription) {
      this.tracksSubscription.unsubscribe();
    }
    if (this.visitsManager) {
      this.visitsManager.destroy();
    }
    if (this.layerControl) {
      this.map.removeControl(this.layerControl);
    }
    if (this.map) {
      this.map.remove();
    }
    console.log("Map controller disconnected");
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

  setupTracksSubscription() {
    this.tracksSubscription = consumer.subscriptions.create("TracksChannel", {
      received: (data) => {
        console.log("Received track update:", data);
        if (this.map && this.map._loaded && this.tracksLayer) {
          this.handleTrackUpdate(data);
        }
      }
    });
  }

  handleTrackUpdate(data) {
    // Get current time range for filtering
    const urlParams = new URLSearchParams(window.location.search);
    const currentStartAt = urlParams.get('start_at') || new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const currentEndAt = urlParams.get('end_at') || new Date().toISOString();

    // Handle the track update
    handleIncrementalTrackUpdate(
      this.tracksLayer,
      data,
      this.map,
      this.userSettings,
      this.distanceUnit,
      currentStartAt,
      currentEndAt
    );

    // If tracks are visible, make sure the layer is properly displayed
    if (this.tracksVisible && this.tracksLayer) {
      if (!this.map.hasLayer(this.tracksLayer)) {
        this.map.addLayer(this.tracksLayer);
      }
    }
  }

  /**
   * Initialize the Live Map Handler
   */
  initializeLiveMapHandler() {
    const layers = {
      markersLayer: this.markersLayer,
      polylinesLayer: this.polylinesLayer,
      heatmapLayer: this.heatmapLayer,
      fogOverlay: this.fogOverlay
    };

    const options = {
      maxPoints: 1000,
      routeOpacity: this.routeOpacity,
      timezone: this.timezone,
      distanceUnit: this.distanceUnit,
      userSettings: this.userSettings,
      clearFogRadius: this.clearFogRadius,
      fogLineThreshold: this.fogLineThreshold,
      // Pass existing data to LiveMapHandler
      existingMarkers: this.markers || [],
      existingMarkersArray: this.markersArray || [],
      existingHeatmapMarkers: this.heatmapMarkers || []
    };

    this.liveMapHandler = new LiveMapHandler(this.map, layers, options);

    // Enable live map handler if live mode is already enabled
    if (this.liveMapEnabled) {
      this.liveMapHandler.enable();
    }
  }

  /**
   * Delegate to LiveMapHandler for memory-efficient point appending
   */
  appendPoint(data) {
    if (this.liveMapHandler && this.liveMapEnabled) {
      this.liveMapHandler.appendPoint(data);
      // Update scratch layer manager with new markers
      if (this.scratchLayerManager) {
        this.scratchLayerManager.updateMarkers(this.markers);
      }
    } else {
      console.warn('LiveMapHandler not initialized or live mode not enabled');
    }
  }

  async initializeScratchLayer() {
    this.scratchLayerManager = new ScratchLayer(this.map, this.markers, this.countryCodesMap, this.apiKey);
    this.scratchLayer = await this.scratchLayerManager.setup();
  }

  toggleScratchLayer() {
    if (this.scratchLayerManager) {
      this.scratchLayerManager.toggle();
    }
  }

  baseMaps() {
    let selectedLayerName = this.userSettings.preferred_map_layer || "OpenStreetMap";
    let maps = createAllMapLayers(this.map, selectedLayerName, this.selfHosted);

    // Add custom map if it exists in settings
    if (this.userSettings.maps && this.userSettings.maps.url) {
      const customLayer = L.tileLayer(this.userSettings.maps.url, {
        maxZoom: 19,
        attribution: "&copy; OpenStreetMap contributors"
      });

      // If this is the preferred layer, add it to the map immediately
      if (selectedLayerName === this.userSettings.maps.name) {
        // Remove any existing base layers first
        Object.values(maps).forEach(layer => {
          if (this.map.hasLayer(layer)) {
            this.map.removeLayer(layer);
          }
        });
        customLayer.addTo(this.map);
      }

      maps[this.userSettings.maps.name] = customLayer;
    } else {
      // If no maps were created (fallback case), add OSM
      if (Object.keys(maps).length === 0) {
        console.warn('No map layers available, adding OSM fallback');
        const osmLayer = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
          maxZoom: 19,
          attribution: "&copy; <a href='http://www.openstreetmap.org/copyright'>OpenStreetMap</a>"
        });
        osmLayer.addTo(this.map);
        maps["OpenStreetMap"] = osmLayer;
      }
      // Note: createAllMapLayers already added the user's preferred layer to the map
    }

    return maps;
  }

  createTreeLayerControl(additionalLayers = {}) {
    // Build base maps tree structure
    const baseMapsTree = {
      label: 'Map Styles',
      children: []
    };

    const maps = this.baseMaps();
    Object.entries(maps).forEach(([name, layer]) => {
      baseMapsTree.children.push({
        label: name,
        layer: layer
      });
    });

    // Build places subtree with tags
    // Store filtered layers for later restoration
    if (!this.placesFilteredLayers) {
      this.placesFilteredLayers = {};
    }
    // Store mapping of tag IDs to layers for persistence
    if (!this.tagLayerMapping) {
      this.tagLayerMapping = {};
    }

    // Create Untagged layer
    const untaggedLayer = this.placesManager?.createFilteredLayer([]) || L.layerGroup();
    this.placesFilteredLayers['Untagged'] = untaggedLayer;
    // Store layer reference with special ID for untagged
    untaggedLayer._placeTagId = 'untagged';

    const placesChildren = [
      {
        label: 'Untagged',
        layer: untaggedLayer
      }
    ];

    // Add individual tag layers
    if (this.userTags && this.userTags.length > 0) {
      this.userTags.forEach(tag => {
        const icon = tag.icon || '📍';
        const label = `${icon} #${tag.name}`;
        const tagLayer = this.placesManager?.createFilteredLayer([tag.id]) || L.layerGroup();
        this.placesFilteredLayers[label] = tagLayer;
        // Store tag ID on the layer itself for easy identification
        tagLayer._placeTagId = tag.id;
        // Store in mapping for lookup by ID
        this.tagLayerMapping[tag.id] = { layer: tagLayer, label: label };
        placesChildren.push({
          label: label,
          layer: tagLayer
        });
      });
    }

    // Build visits subtree
    const visitsChildren = [
      {
        label: 'Suggested',
        layer: this.visitsManager?.getVisitCirclesLayer() || L.layerGroup()
      },
      {
        label: 'Confirmed',
        layer: this.visitsManager?.getConfirmedVisitCirclesLayer() || L.layerGroup()
      }
    ];

    // Build the overlays tree structure
    const overlaysTree = {
      label: 'Layers',
      selectAllCheckbox: false,
      children: [
        {
          label: 'Points',
          layer: this.markersLayer
        },
        {
          label: 'Routes',
          layer: this.polylinesLayer
        },
        {
          label: 'Tracks',
          layer: this.tracksLayer
        },
        {
          label: 'Heatmap',
          layer: this.heatmapLayer
        },
        {
          label: 'Fog of War',
          layer: this.fogOverlay
        },
        {
          label: 'Scratch map',
          layer: this.scratchLayerManager?.getLayer() || L.layerGroup()
        },
        {
          label: 'Areas',
          layer: this.areasLayer
        },
        {
          label: 'Photos',
          layer: this.photoMarkers
        },
        {
          label: 'Visits',
          selectAllCheckbox: true,
          children: visitsChildren
        },
        {
          label: 'Places',
          selectAllCheckbox: true,
          children: placesChildren
        }
      ]
    };

    // Add Family Members layer if available
    if (additionalLayers['Family Members']) {
      overlaysTree.children.push({
        label: 'Family Members',
        layer: additionalLayers['Family Members']
      });
    }

    // Create the tree control
    return L.control.layers.tree(
      baseMapsTree,
      overlaysTree,
      {
        namedToggle: false,
        collapsed: true,
        position: 'topright'
      }
    );
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

    // Add event listeners for overlay layer changes to keep routes/tracks selector in sync
    this.map.on('overlayadd', (event) => {
      // Track place tag layer restoration
      if (this.isRestoringLayers && event.layer && this.placesFilteredLayers) {
        // Check if this is a place tag layer being restored
        const isPlaceTagLayer = Object.values(this.placesFilteredLayers).includes(event.layer);
        if (isPlaceTagLayer && this.restoredPlaceTagLayers !== undefined) {
          const tagId = event.layer._placeTagId;
          this.restoredPlaceTagLayers.add(tagId);

          // Check if all expected place tag layers have been restored
          if (this.restoredPlaceTagLayers.size >= this.expectedPlaceTagLayerCount) {
            this.isRestoringLayers = false;
          }
        }
      }

      // Save enabled layers whenever a layer is added (unless we're restoring from settings)
      if (!this.isRestoringLayers) {
        this.saveEnabledLayers();
      }

      if (event.name === 'Routes') {
        this.handleRouteLayerToggle('routes');
        // Re-establish event handlers when routes are manually added
        if (event.layer === this.polylinesLayer) {
          reestablishPolylineEventHandlers(this.polylinesLayer, this.map, this.userSettings, this.distanceUnit);
        }
      } else if (event.name === 'Tracks') {
        this.handleRouteLayerToggle('tracks');
      } else if (event.name === 'Areas') {
        // Show draw control when Areas layer is enabled
        if (this.drawControl && !this.map.hasControl && !this.map._controlCorners.topleft.querySelector('.leaflet-draw')) {
          this.map.addControl(this.drawControl);
        }
      } else if (event.layer === this.photoMarkers) {
        // Load photos when Photos layer is enabled
        console.log('Photos layer enabled via layer control');
        const urlParams = new URLSearchParams(window.location.search);
        const startDate = urlParams.get('start_at') || new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const endDate = urlParams.get('end_at') || new Date().toISOString();

        console.log('Fetching photos for date range:', { startDate, endDate });
        fetchAndDisplayPhotos({
          map: this.map,
          photoMarkers: this.photoMarkers,
          apiKey: this.apiKey,
          startDate: startDate,
          endDate: endDate,
          userSettings: this.userSettings
        });
      } else if (event.name === 'Suggested' || event.name === 'Confirmed') {
        // Load visits when layer is enabled
        console.log(`${event.name} layer enabled via layer control`);
        if (this.visitsManager && typeof this.visitsManager.fetchAndDisplayVisits === 'function') {
          // Fetch and populate the visits - this will create circles and update drawer if open
          this.visitsManager.fetchAndDisplayVisits();
        }
      } else if (event.name === 'Scratch map') {
        // Add scratch map layer
        console.log('Scratch map layer enabled via layer control');
        if (this.scratchLayerManager) {
          this.scratchLayerManager.addToMap();
        }
      } else if (event.name === 'Fog of War') {
        // Fog of war layer re-enabled, redraw the fog
        // Note: this.fogOverlay already holds the correct reference from initialization
        this.updateFog(this.markers || [], this.clearFogRadius, this.fogLineThreshold);
      }

      // Manage pane visibility when layers are manually toggled
      this.updatePaneVisibilityAfterLayerChange();
    });

    this.map.on('overlayremove', (event) => {
      // Save enabled layers whenever a layer is removed (unless we're restoring from settings)
      if (!this.isRestoringLayers) {
        this.saveEnabledLayers();
      }

      if (event.name === 'Routes' || event.name === 'Tracks') {
        // Don't auto-switch when layers are manually turned off
        // Just update the radio button state to reflect current visibility
        this.updateRadioButtonState();

        // Manage pane visibility when layers are manually toggled
        this.updatePaneVisibilityAfterLayerChange();
      } else if (event.name === 'Areas') {
        // Hide draw control when Areas layer is disabled
        if (this.drawControl && this.map._controlCorners.topleft.querySelector('.leaflet-draw')) {
          this.map.removeControl(this.drawControl);
        }
      } else if (event.name === 'Suggested') {
        // Clear suggested visits when layer is disabled
        console.log('Suggested layer disabled via layer control');
        if (this.visitsManager) {
          // Clear the visit circles when layer is disabled
          this.visitsManager.visitCircles.clearLayers();
        }
      } else if (event.name === 'Scratch map') {
        // Handle scratch map layer removal
        console.log('Scratch map layer disabled via layer control');
        if (this.scratchLayerManager) {
          this.scratchLayerManager.remove();
        }
      }
    });

    // Listen for place creation events to disable creation mode
    document.addEventListener('place:created', () => {
      this.disablePlaceCreationMode();
    });

    document.addEventListener('place:create:cancelled', () => {
      this.disablePlaceCreationMode();
    });
  }

  updatePreferredBaseLayer(selectedLayerName) {
    fetch('/api/v1/settings', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
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

  saveEnabledLayers() {
    // Don't save if we're restoring layers from settings
    if (this.isRestoringLayers) {
      console.log('[saveEnabledLayers] Skipping save - currently restoring layers from settings');
      return;
    }

    const enabledLayers = [];

    // Iterate through all layers on the map to determine which are enabled
    // This is more reliable than parsing the DOM
    const layersToCheck = {
      'Points': this.markersLayer,
      'Routes': this.polylinesLayer,
      'Tracks': this.tracksLayer,
      'Heatmap': this.heatmapLayer,
      'Fog of War': this.fogOverlay,
      'Scratch map': this.scratchLayerManager?.getLayer(),
      'Areas': this.areasLayer,
      'Photos': this.photoMarkers,
      'Suggested': this.visitsManager?.getVisitCirclesLayer(),
      'Confirmed': this.visitsManager?.getConfirmedVisitCirclesLayer(),
      'Family Members': window.familyMembersController?.familyMarkersLayer
    };

    // Check standard layers
    Object.entries(layersToCheck).forEach(([name, layer]) => {
      if (layer && this.map.hasLayer(layer)) {
        enabledLayers.push(name);
      }
    });

    // Check place tag layers - save as "place_tag:ID" format
    if (this.placesFilteredLayers) {
      Object.values(this.placesFilteredLayers).forEach(layer => {
        if (layer && this.map.hasLayer(layer) && layer._placeTagId !== undefined) {
          enabledLayers.push(`place_tag:${layer._placeTagId}`);
        }
      });
    } else {
      console.warn('[saveEnabledLayers] placesFilteredLayers is not initialized');
    }

    fetch('/api/v1/settings', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        settings: {
          enabled_map_layers: enabledLayers
        },
      }),
    })
    .then((response) => response.json())
    .then((data) => {
      if (data.status === 'success') {
        console.log('Enabled layers saved:', enabledLayers);
        // showFlashMessage('notice', 'Map layer preferences saved');
      } else {
        console.error('Failed to save enabled layers:', data.message);
        showFlashMessage('error', `Failed to save layer preferences: ${data.message}`);
      }
    })
    .catch(error => {
      console.error('Error saving enabled layers:', error);
      showFlashMessage('error', 'Error saving layer preferences');
    });
  }

  deletePoint(id, apiKey) {
    fetch(`/api/v1/points/${id}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
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
        this.layerControl = this.createTreeLayerControl();
        this.map.addControl(this.layerControl);
      }

      // Update heatmap
      this.heatmapLayer.setLatLngs(this.markers.map(marker => [marker[0], marker[1], 0.2]));

      // Update fog if enabled
      if (this.map.hasLayer(this.fogOverlay)) {
        this.updateFog(this.markers, this.clearFogRadius, this.fogLineThreshold);
      }

      // Show success message
      showFlashMessage('notice', 'Point deleted successfully');
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

      // Update scratch layer manager with updated markers
      if (this.scratchLayerManager) {
        this.scratchLayerManager.updateMarkers(this.markers);
      }
    }
  }

  updateFog(markers, clearFogRadius, fogLineThreshold) {
    // Call the fog overlay's updateFog method if it exists
    if (this.fogOverlay && typeof this.fogOverlay.updateFog === 'function') {
      this.fogOverlay.updateFog(markers, clearFogRadius, fogLineThreshold);
    } else {
      // Fallback for when fog overlay isn't available
      const fog = document.getElementById('fog');
      if (!fog) {
        initializeFogCanvas(this.map);
      }
      requestAnimationFrame(() => drawFogCanvas(this.map, markers, clearFogRadius, fogLineThreshold));
    }
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
      }
    });

    // Handle circle creation
    this.map.on('draw:created', (event) => {
      const layer = event.layer;

      if (event.layerType === 'circle') {
        try {
          // Add the layer to the map first
          layer.addTo(this.map);
          handleAreaCreated(this.areasLayer, layer, this.apiKey);
        } catch (error) {
          console.error("Error in handleAreaCreated:", error);
          console.error(error.stack); // Add stack trace
        }
      }
    });
  }

  addSettingsButton() {
    if (this.settingsButtonAdded) return;

    // Define the custom control
    const SettingsControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'map-settings-button tooltip tooltip-right');
        button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-cog-icon lucide-cog"><path d="M11 10.27 7 3.34"/><path d="m11 13.73-4 6.93"/><path d="M12 22v-2"/><path d="M12 2v2"/><path d="M14 12h8"/><path d="m17 20.66-1-1.73"/><path d="m17 3.34-1 1.73"/><path d="M2 12h2"/><path d="m20.66 17-1.73-1"/><path d="m20.66 7-1.73 1"/><path d="m3.34 17 1.73-1"/><path d="m3.34 7 1.73 1"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="12" r="8"/></svg>'; // Gear icon
        button.setAttribute('data-tip', 'Settings');

        // Style the button with theme-aware styling
        applyThemeToButton(button, this.userTheme);
        button.style.width = '30px';
        button.style.height = '30px';
        button.style.display = 'flex';
        button.style.alignItems = 'center';
        button.style.justifyContent = 'center';
        button.style.padding = '0';
        button.style.borderRadius = '4px';

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

  addInfoToggleButton() {
    // Store reference to the controller instance for use in the control
    const controller = this;

    const InfoToggleControl = L.Control.extend({
      options: {
        position: 'bottomleft'
      },
      onAdd: function(map) {
        const container = L.DomUtil.create('div', 'leaflet-bar leaflet-control');
        const button = L.DomUtil.create('button', 'map-info-toggle-button tooltip tooltip-right', container);
        button.setAttribute('data-tip', 'Toggle footer visibility');

        // Lucide info icon
        button.innerHTML = `
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-info">
            <circle cx="12" cy="12" r="10"></circle>
            <path d="M12 16v-4"></path>
            <path d="M12 8h.01"></path>
          </svg>
        `;

        // Style the button with theme-aware styling
        applyThemeToButton(button, controller.userTheme);
        button.style.width = '34px';
        button.style.height = '34px';
        button.style.display = 'flex';
        button.style.alignItems = 'center';
        button.style.justifyContent = 'center';
        button.style.cursor = 'pointer';
        button.style.border = 'none';
        button.style.borderRadius = '4px';

        // Disable map interactions when clicking the button
        L.DomEvent.disableClickPropagation(container);

        // Toggle footer visibility on button click
        L.DomEvent.on(button, 'click', () => {
          controller.toggleFooterVisibility();
        });

        return container;
      }
    });

    // Add the control to the map
    this.map.addControl(new InfoToggleControl());
  }

  toggleFooterVisibility() {
    // Toggle the page footer
    const footer = document.getElementById('map-footer');
    if (!footer) return;

    const isCurrentlyHidden = footer.classList.contains('hidden');

    // Toggle Tailwind's hidden class
    footer.classList.toggle('hidden');

    // Adjust bottom controls position based on footer visibility
    if (isCurrentlyHidden) {
      // Footer is being shown - move controls up
      setTimeout(() => {
        const footerHeight = footer.offsetHeight;
        // Add extra 20px margin above footer
        this.adjustBottomControls(footerHeight + 20);
      }, 10); // Small delay to ensure footer is rendered
    } else {
      // Footer is being hidden - reset controls position
      this.adjustBottomControls(10); // Back to default padding
    }

    // Add click event to close footer when clicking on it (only add once)
    if (!footer.dataset.clickHandlerAdded) {
      footer.addEventListener('click', (e) => {
        // Only close if clicking the footer itself, not its contents
        if (e.target === footer) {
          footer.classList.add('hidden');
          this.adjustBottomControls(10); // Reset controls position
        }
      });
      footer.dataset.clickHandlerAdded = 'true';
    }
  }

  adjustBottomControls(paddingBottom) {
    // Adjust all bottom Leaflet controls
    const bottomLeftControls = this.map.getContainer().querySelector('.leaflet-bottom.leaflet-left');
    const bottomRightControls = this.map.getContainer().querySelector('.leaflet-bottom.leaflet-right');

    if (bottomLeftControls) {
      bottomLeftControls.style.setProperty('padding-bottom', `${paddingBottom}px`, 'important');
    }
    if (bottomRightControls) {
      bottomRightControls.style.setProperty('padding-bottom', `${paddingBottom}px`, 'important');
    }
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
        <form id="settings-form" class="space-y-3">
          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Route Opacity, %</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="route-opacity" name="route_opacity" min="10" max="100" step="10" value="${Math.round(this.routeOpacity * 100)}">
              <label for="route_opacity_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Fog of War radius</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="fog_of_war_meters" name="fog_of_war_meters" min="5" max="200" step="1" value="${this.clearFogRadius}">
              <label for="fog_of_war_meters_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Fog of War threshold</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="fog_of_war_threshold" name="fog_of_war_threshold" step="1" value="${this.userSettings.fog_of_war_threshold}">
              <label for="fog_of_war_threshold_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Meters between routes</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="meters_between_routes" name="meters_between_routes" step="1" value="${this.userSettings.meters_between_routes}">
              <label for="meters_between_routes_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Minutes between routes</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="minutes_between_routes" name="minutes_between_routes" step="1" value="${this.userSettings.minutes_between_routes}">
              <label for="minutes_between_routes_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Time threshold minutes</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="time_threshold_minutes" name="time_threshold_minutes" step="1" value="${this.userSettings.time_threshold_minutes}">
              <label for="time_threshold_minutes_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Merge threshold minutes</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="number" class="input input-bordered input-sm join-item flex-1" id="merge_threshold_minutes" name="merge_threshold_minutes" step="1" value="${this.userSettings.merge_threshold_minutes}">
              <label for="merge_threshold_minutes_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Points rendering mode</span>
              <label for="points_rendering_mode_info" class="btn btn-xs btn-ghost cursor-pointer">?</label>
            </label>
            <div class="flex flex-col gap-2">
              <label class="label cursor-pointer justify-start gap-2 py-1">
                <input type="radio" id="raw" name="points_rendering_mode" class="radio radio-sm" value="raw" ${this.pointsRenderingModeChecked('raw')} />
                <span class="label-text text-xs">Raw</span>
              </label>
              <label class="label cursor-pointer justify-start gap-2 py-1">
                <input type="radio" id="simplified" name="points_rendering_mode" class="radio radio-sm" value="simplified" ${this.pointsRenderingModeChecked('simplified')} />
                <span class="label-text text-xs">Simplified</span>
              </label>
            </div>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer py-1">
              <span class="label-text text-xs">Live Map</span>
              <div class="flex items-center gap-1">
                <label for="live_map_enabled_info" class="btn btn-xs btn-ghost cursor-pointer">?</label>
                <input type="checkbox" id="live_map_enabled" name="live_map_enabled" class="checkbox checkbox-sm" ${this.liveMapEnabledChecked(true)} />
              </div>
            </label>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer py-1">
              <span class="label-text text-xs">Speed-colored routes</span>
              <div class="flex items-center gap-1">
                <label for="speed_colored_routes_info" class="btn btn-xs btn-ghost cursor-pointer">?</label>
                <input type="checkbox" id="speed_colored_routes" name="speed_colored_routes" class="checkbox checkbox-sm" ${this.speedColoredRoutesChecked()} />
              </div>
            </label>
          </div>

          <div class="form-control">
            <label class="label py-1">
              <span class="label-text text-xs">Speed color scale</span>
            </label>
            <div class="join join-horizontal w-full">
              <input type="text" class="input input-bordered input-sm join-item flex-1" id="speed_color_scale" name="speed_color_scale" value="${this.speedColorScale}">
              <label for="speed_color_scale_info" class="btn btn-sm btn-ghost join-item cursor-pointer">?</label>
            </div>
            <button type="button" id="edit-gradient-btn" class="btn btn-sm mt-2 w-full">Edit Colors</button>
          </div>

          <div class="divider my-2"></div>

          <button type="submit" class="btn btn-sm btn-primary w-full">Update</button>
        </form>
      `;

      // Style the panel with theme-aware styling
      applyThemeToPanel(div, this.userTheme);
      div.style.padding = '10px';
      div.style.width = '220px';
      div.style.maxHeight = 'calc(60vh - 20px)';
      div.style.overflowY = 'auto';

      // Prevent map interactions when interacting with the form
      L.DomEvent.disableClickPropagation(div);
      L.DomEvent.disableScrollPropagation(div);

       // Attach event listener to the "Edit Gradient" button:
      const editBtn = div.querySelector("#edit-gradient-btn");
      if (editBtn) {
        editBtn.addEventListener("click", this.showGradientEditor.bind(this));
      }

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

    // Convert percentage to decimal for route_opacity
    const opacityValue = event.target.route_opacity.value.replace('%', '');
    const decimalOpacity = parseFloat(opacityValue) / 100;

    fetch('/api/v1/settings', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        settings: {
          route_opacity: decimalOpacity.toString(),
          fog_of_war_meters: event.target.fog_of_war_meters.value,
          fog_of_war_threshold: event.target.fog_of_war_threshold.value,
          meters_between_routes: event.target.meters_between_routes.value,
          minutes_between_routes: event.target.minutes_between_routes.value,
          time_threshold_minutes: event.target.time_threshold_minutes.value,
          merge_threshold_minutes: event.target.merge_threshold_minutes.value,
          points_rendering_mode: event.target.points_rendering_mode.value,
          live_map_enabled: event.target.live_map_enabled.checked,
          speed_colored_routes: event.target.speed_colored_routes.checked,
          speed_color_scale: event.target.speed_color_scale.value
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
            if (this.liveMapHandler) {
              this.liveMapHandler.enable();
            }
          } else {
            if (this.liveMapHandler) {
              this.liveMapHandler.disable();
            }
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
    // Show loading indicator
    const loadingDiv = document.createElement('div');
    loadingDiv.className = 'map-loading-overlay';
    loadingDiv.innerHTML = '<div class="loading loading-lg">Updating map...</div>';
    document.body.appendChild(loadingDiv);

    try {
      // Update settings first
      if (newSettings.speed_colored_routes !== this.userSettings.speed_colored_routes) {
        if (this.polylinesLayer) {
          updatePolylinesColors(
            this.polylinesLayer,
            newSettings.speed_colored_routes,
            newSettings.speed_color_scale
          );
        }
      }

      if (newSettings.speed_color_scale !== this.userSettings.speed_color_scale) {
        if (this.polylinesLayer) {
          updatePolylinesColors(
            this.polylinesLayer,
            newSettings.speed_colored_routes,
            newSettings.speed_color_scale
          );
        }
      }

      if (newSettings.route_opacity !== this.userSettings.route_opacity) {
        const newOpacity = parseFloat(newSettings.route_opacity) || 0.6;
        if (this.polylinesLayer) {
          updatePolylinesOpacity(this.polylinesLayer, newOpacity);
        }
      }

      // Update the local settings
      this.userSettings = { ...this.userSettings, ...newSettings };
      // Store the value as decimal internally, but display as percentage in UI
      this.routeOpacity = parseFloat(newSettings.route_opacity) || 0.6;
      this.clearFogRadius = parseInt(newSettings.fog_of_war_meters) || 50;
      this.liveMapEnabled = newSettings.live_map_enabled || false;

      // Update the DOM data attribute to keep it in sync
      const mapElement = document.getElementById('map');
      if (mapElement) {
        mapElement.setAttribute('data-user_settings', JSON.stringify(this.userSettings));
        // Update theme if it changed
        if (newSettings.theme && newSettings.theme !== this.userTheme) {
          this.userTheme = newSettings.theme;
          mapElement.setAttribute('data-user_theme', this.userTheme);

          // Dispatch theme change event for other controllers
          document.dispatchEvent(new CustomEvent('theme:changed', {
            detail: { theme: this.userTheme }
          }));
        }
      }

      // Store current layer states
      const layerStates = {
        Points: this.map.hasLayer(this.markersLayer),
        Routes: this.map.hasLayer(this.polylinesLayer),
        Tracks: this.tracksLayer ? this.map.hasLayer(this.tracksLayer) : false,
        Heatmap: this.map.hasLayer(this.heatmapLayer),
        "Fog of War": this.map.hasLayer(this.fogOverlay),
        "Scratch map": this.scratchLayerManager?.isVisible() || false,
        Areas: this.map.hasLayer(this.areasLayer),
        Photos: this.map.hasLayer(this.photoMarkers)
      };

      // Remove only the layer control
      if (this.layerControl) {
        this.map.removeControl(this.layerControl);
      }

      // Create new controls layer object
      const controlsLayer = {
        Points: this.markersLayer || L.layerGroup(),
        Routes: this.polylinesLayer || L.layerGroup(),
        Tracks: this.tracksLayer || L.layerGroup(),
        Heatmap: this.heatmapLayer || L.heatLayer([]),
        "Fog of War": this.fogOverlay,
        "Scratch map": this.scratchLayer || L.layerGroup(),
        Areas: this.areasLayer || L.layerGroup(),
        Photos: this.photoMarkers || L.layerGroup()
      };

      // Re-add the layer control in the same position
      this.layerControl = this.createTreeLayerControl();
      this.map.addControl(this.layerControl);

      // Restore layer visibility states
      Object.entries(layerStates).forEach(([name, wasVisible]) => {
        const layer = controlsLayer[name];
        if (wasVisible && layer) {
          layer.addTo(this.map);
          // Re-establish event handlers for polylines layer when it's re-added
          if (name === 'Routes' && layer === this.polylinesLayer) {
            reestablishPolylineEventHandlers(this.polylinesLayer, this.map, this.userSettings, this.distanceUnit);
          }
        } else if (layer && this.map.hasLayer(layer)) {
          this.map.removeLayer(layer);
        }
      });

      // Manage pane visibility based on which layers are visible
      const routesVisible = this.map.hasLayer(this.polylinesLayer);
      const tracksVisible = this.tracksLayer && this.map.hasLayer(this.tracksLayer);

      if (routesVisible && !tracksVisible) {
        managePaneVisibility(this.map, 'routes');
      } else if (tracksVisible && !routesVisible) {
        managePaneVisibility(this.map, 'tracks');
      } else {
        managePaneVisibility(this.map, 'both');
      }

    } catch (error) {
      console.error('Error updating map settings:', error);
      console.error(error.stack);
    } finally {
      // Remove loading indicator
      setTimeout(() => {
        document.body.removeChild(loadingDiv);
      }, 500);
    }
  }

  initializeTopRightButtons() {
    // Add all top-right buttons in the correct order:
    // 1. Select Area, 2. Add Visit, 3. Create Place, 4. Open Calendar, 5. Open Drawer
    // Note: Layer control is added separately and appears at the top

    this.topRightControls = addTopRightButtons(
      this.map,
      {
        onSelectArea: () => this.visitsManager.toggleSelectionMode(),
        // onAddVisit is intentionally null - the add_visit_controller will attach its handler
        onAddVisit: null,
        onCreatePlace: () => this.togglePlaceCreationMode(),
        onToggleCalendar: () => this.toggleRightPanel(),
        onToggleDrawer: () => this.visitsManager.toggleDrawer()
      },
      this.userTheme
    );

    // Add CSS for selection button active state (needed by visits manager)
    if (!document.getElementById('selection-tool-active-style')) {
      const style = document.createElement('style');
      style.id = 'selection-tool-active-style';
      style.textContent = `
        #selection-tool-button.active {
          border: 2px dashed #3388ff !important;
          box-shadow: 0 0 8px rgba(51, 136, 255, 0.5) !important;
        }
      `;
      document.head.appendChild(style);
    }
  }

  shouldShowTracksSelector() {
    const urlParams = new URLSearchParams(window.location.search);
    return urlParams.get('tracks_debug') === 'true';
  }

  addRoutesTracksSelector() {
    // Store reference to the controller instance for use in the control
    const controller = this;

    const RouteTracksControl = L.Control.extend({
      onAdd: function(map) {
        const container = L.DomUtil.create('div', 'routes-tracks-selector leaflet-bar');
        applyThemeToControl(container, controller.userTheme, {
          padding: '8px',
          borderRadius: '4px',
          fontSize: '12px',
          lineHeight: '1.2'
        });

        // Get saved preference or default to 'routes'
        const savedPreference = localStorage.getItem('mapRouteMode') || 'routes';

        container.innerHTML = `
          <div style="margin-bottom: 4px; font-weight: bold; text-align: center;">Display</div>
          <div>
            <label style="display: block; margin-bottom: 4px; cursor: pointer;">
              <input type="radio" name="route-mode" value="routes" ${savedPreference === 'routes' ? 'checked' : ''} style="margin-right: 4px;">
              Routes
            </label>
            <label style="display: block; cursor: pointer;">
              <input type="radio" name="route-mode" value="tracks" ${savedPreference === 'tracks' ? 'checked' : ''} style="margin-right: 4px;">
              Tracks
            </label>
          </div>
        `;

        // Disable map interactions when clicking the control
        L.DomEvent.disableClickPropagation(container);

        // Add change event listeners
        const radioButtons = container.querySelectorAll('input[name="route-mode"]');
        radioButtons.forEach(radio => {
          L.DomEvent.on(radio, 'change', () => {
            if (radio.checked) {
              controller.switchRouteMode(radio.value);
            }
          });
        });

        return container;
      }
    });

    // Add the control to the map
    this.map.addControl(new RouteTracksControl({ position: 'topleft' }));

    // Apply initial state based on saved preference
    const savedPreference = localStorage.getItem('mapRouteMode') || 'routes';
    this.switchRouteMode(savedPreference, true);

    // Set initial pane visibility
    this.updatePaneVisibilityAfterLayerChange();
  }

    switchRouteMode(mode, isInitial = false) {
    // Save preference to localStorage
    localStorage.setItem('mapRouteMode', mode);

    if (mode === 'routes') {
      // Hide tracks layer if it exists and is visible
      if (this.tracksLayer && this.map.hasLayer(this.tracksLayer)) {
        this.map.removeLayer(this.tracksLayer);
      }

      // Show routes layer if it exists and is not visible
      if (this.polylinesLayer && !this.map.hasLayer(this.polylinesLayer)) {
        this.map.addLayer(this.polylinesLayer);
        // Re-establish event handlers after adding the layer back
        reestablishPolylineEventHandlers(this.polylinesLayer, this.map, this.userSettings, this.distanceUnit);
      } else if (this.polylinesLayer) {
        reestablishPolylineEventHandlers(this.polylinesLayer, this.map, this.userSettings, this.distanceUnit);
      }

      // Manage pane visibility to fix z-index blocking
      managePaneVisibility(this.map, 'routes');

      // Update layer control checkboxes
      this.updateLayerControlCheckboxes('Routes', true);
      this.updateLayerControlCheckboxes('Tracks', false);
    } else if (mode === 'tracks') {
      // Hide routes layer if it exists and is visible
      if (this.polylinesLayer && this.map.hasLayer(this.polylinesLayer)) {
        this.map.removeLayer(this.polylinesLayer);
      }

      // Show tracks layer if it exists and is not visible
      if (this.tracksLayer && !this.map.hasLayer(this.tracksLayer)) {
        this.map.addLayer(this.tracksLayer);
      }

      // Manage pane visibility to fix z-index blocking
      managePaneVisibility(this.map, 'tracks');

      // Update layer control checkboxes
      this.updateLayerControlCheckboxes('Routes', false);
      this.updateLayerControlCheckboxes('Tracks', true);
    }
  }

  updateLayerControlCheckboxes(layerName, isVisible) {
    // Find the layer control input for the specified layer
    const layerControlContainer = document.querySelector('.leaflet-control-layers');
    if (!layerControlContainer) return;

    const inputs = layerControlContainer.querySelectorAll('input[type="checkbox"]');
    inputs.forEach(input => {
      const label = input.nextElementSibling;
      if (label && label.textContent.trim() === layerName) {
        input.checked = isVisible;
      }
    });
  }

  handleRouteLayerToggle(mode) {
    // Update the radio button selection
    const radioButtons = document.querySelectorAll('input[name="route-mode"]');
    radioButtons.forEach(radio => {
      if (radio.value === mode) {
        radio.checked = true;
      }
    });

    // Switch to the selected mode and enforce mutual exclusivity
    this.switchRouteMode(mode);
  }

  updateRadioButtonState() {
    // Update radio buttons to reflect current layer visibility
    const routesVisible = this.polylinesLayer && this.map.hasLayer(this.polylinesLayer);
    const tracksVisible = this.tracksLayer && this.map.hasLayer(this.tracksLayer);

    const radioButtons = document.querySelectorAll('input[name="route-mode"]');
    radioButtons.forEach(radio => {
      if (radio.value === 'routes' && routesVisible && !tracksVisible) {
        radio.checked = true;
      } else if (radio.value === 'tracks' && tracksVisible && !routesVisible) {
        radio.checked = true;
      }
    });
  }

  updatePaneVisibilityAfterLayerChange() {
    // Update pane visibility based on current layer visibility
    const routesVisible = this.polylinesLayer && this.map.hasLayer(this.polylinesLayer);
    const tracksVisible = this.tracksLayer && this.map.hasLayer(this.tracksLayer);

    if (routesVisible && !tracksVisible) {
      managePaneVisibility(this.map, 'routes');
    } else if (tracksVisible && !routesVisible) {
      managePaneVisibility(this.map, 'tracks');
    } else {
      managePaneVisibility(this.map, 'both');
    }
  }

    initializeLayersFromSettings() {
    // Initialize layer visibility based on user settings or defaults
    // This method sets up the initial state of overlay layers

    // Get enabled layers from user settings
    const enabledLayers = this.userSettings.enabled_map_layers || ['Points', 'Routes', 'Heatmap'];
    console.log('Initializing layers from settings:', enabledLayers);

    // Standard layers mapping
    const controlsLayer = {
      'Points': this.markersLayer,
      'Routes': this.polylinesLayer,
      'Tracks': this.tracksLayer,
      'Heatmap': this.heatmapLayer,
      'Fog of War': this.fogOverlay,
      'Scratch map': this.scratchLayerManager?.getLayer(),
      'Areas': this.areasLayer,
      'Photos': this.photoMarkers,
      'Suggested': this.visitsManager?.getVisitCirclesLayer(),
      'Confirmed': this.visitsManager?.getConfirmedVisitCirclesLayer(),
      'Family Members': window.familyMembersController?.familyMarkersLayer
    };

    // Apply saved layer preferences for standard layers
    Object.entries(controlsLayer).forEach(([name, layer]) => {
      if (!layer) {
        if (enabledLayers.includes(name)) {
          console.log(`Layer ${name} is in enabled layers but layer object is null/undefined`);
        }
        return;
      }

      const shouldBeEnabled = enabledLayers.includes(name);
      const isCurrentlyEnabled = this.map.hasLayer(layer);

      if (name === 'Family Members') {
        console.log('Family Members layer check:', {
          shouldBeEnabled,
          isCurrentlyEnabled,
          layerExists: !!layer,
          controllerExists: !!window.familyMembersController
        });
      }

      if (shouldBeEnabled && !isCurrentlyEnabled) {
        // Add layer to map
        layer.addTo(this.map);
        console.log(`Enabled layer: ${name}`);

        // Trigger special initialization for certain layers
        // Note: Photos fetch is handled by the overlayadd event handler
        if (name === 'Fog of War') {
          this.updateFog(this.markers, this.clearFogRadius, this.fogLineThreshold);
        } else if (name === 'Suggested' || name === 'Confirmed') {
          if (this.visitsManager && typeof this.visitsManager.fetchAndDisplayVisits === 'function') {
            this.visitsManager.fetchAndDisplayVisits();
          }
        } else if (name === 'Scratch map') {
          if (this.scratchLayerManager) {
            this.scratchLayerManager.addToMap();
          }
        } else if (name === 'Routes') {
          // Re-establish event handlers for routes layer
          reestablishPolylineEventHandlers(this.polylinesLayer, this.map, this.userSettings, this.distanceUnit);
        } else if (name === 'Areas') {
          // Show draw control when Areas layer is enabled
          if (this.drawControl && !this.map._controlCorners.topleft.querySelector('.leaflet-draw')) {
            this.map.addControl(this.drawControl);
          }
        } else if (name === 'Family Members') {
          // Refresh family locations when layer is restored
          if (window.familyMembersController && typeof window.familyMembersController.refreshFamilyLocations === 'function') {
            window.familyMembersController.refreshFamilyLocations();
          }
        }
      } else if (!shouldBeEnabled && isCurrentlyEnabled) {
        // Remove layer from map
        this.map.removeLayer(layer);
        console.log(`Disabled layer: ${name}`);
      }
    });

    // Place tag layers will be restored by updateTreeControlCheckboxes
    // which triggers the tree control's change events to properly add/remove layers

    // Track expected place tag layers to be restored
    const expectedPlaceTagLayers = enabledLayers.filter(key => key.startsWith('place_tag:'));
    this.restoredPlaceTagLayers = new Set();
    this.expectedPlaceTagLayerCount = expectedPlaceTagLayers.length;

    // Set flag to prevent saving during layer restoration
    this.isRestoringLayers = true;

    // Update the tree control checkboxes to reflect the layer states
    // The tree control will handle adding/removing layers when checkboxes change
    // Wait a bit for the tree control to be fully initialized
    setTimeout(() => {
      this.updateTreeControlCheckboxes(enabledLayers);

      // Set a fallback timeout in case not all layers get added
      setTimeout(() => {
        if (this.isRestoringLayers) {
          console.warn('[initializeLayersFromSettings] Timeout reached, forcing restoration complete');
          this.isRestoringLayers = false;
        }
      }, 2000);
    }, 200);
  }

  updateTreeControlCheckboxes(enabledLayers) {
    const layerControl = document.querySelector('.leaflet-control-layers');
    if (!layerControl) {
      console.log('Layer control not found, skipping checkbox update');
      return;
    }

    // Extract place tag IDs from enabledLayers
    const enabledTagIds = new Set();
    enabledLayers.forEach(key => {
      if (key.startsWith('place_tag:')) {
        const tagId = key.replace('place_tag:', '');
        enabledTagIds.add(tagId === 'untagged' ? 'untagged' : parseInt(tagId));
      }
    });

    // Find and check/uncheck all layer checkboxes based on saved state
    const inputs = layerControl.querySelectorAll('input[type="checkbox"]');
    inputs.forEach(input => {
      const label = input.closest('label') || input.nextElementSibling;
      if (label) {
        const layerName = label.textContent.trim();

        // Check if this is a standard layer
        let shouldBeEnabled = enabledLayers.includes(layerName);

        // Also check if this is a place tag layer
        let placeLayer = null;
        if (this.placesFilteredLayers) {
          placeLayer = this.placesFilteredLayers[layerName];
          if (placeLayer && placeLayer._placeTagId !== undefined) {
            // This is a place tag layer - check if it should be enabled
            const placeLayerEnabled = enabledTagIds.has(placeLayer._placeTagId);
            if (placeLayerEnabled) {
              shouldBeEnabled = true;
            }
          }
        }

        // Skip group headers that might have checkboxes
        if (layerName && !layerName.includes('Map Styles') && !layerName.includes('Layers')) {
          if (shouldBeEnabled !== input.checked) {
            // Checkbox state needs to change - simulate a click to trigger tree control
            // The tree control listens for click events, not change events
            input.click();
          } else if (shouldBeEnabled && placeLayer && !this.map.hasLayer(placeLayer)) {
            // Checkbox is already checked but layer isn't on map (edge case)
            // This can happen if the checkbox was checked in HTML but layer wasn't added
            // Manually add the layer since clicking won't help (checkbox is already checked)
            placeLayer.addTo(this.map);
          }
        }
      }
    });
  }

  setupFamilyLayerListener() {
    // Listen for when the Family Members layer becomes available
    document.addEventListener('family:layer:ready', (event) => {
      console.log('Family layer ready event received');
      const enabledLayers = this.userSettings.enabled_map_layers || [];

      // Check if Family Members should be enabled based on saved settings
      if (enabledLayers.includes('Family Members')) {
        const layer = event.detail.layer;
        if (layer && !this.map.hasLayer(layer)) {
          // Set flag to prevent saving during restoration
          this.isRestoringLayers = true;

          layer.addTo(this.map);
          console.log('Enabled layer: Family Members (from ready event)');

          // Refresh family locations
          if (window.familyMembersController && typeof window.familyMembersController.refreshFamilyLocations === 'function') {
            window.familyMembersController.refreshFamilyLocations();
          }

          // Reset flag after a short delay to allow all events to complete
          setTimeout(() => {
            this.isRestoringLayers = false;
          }, 100);
        }
      }
    }, { once: true }); // Only listen once
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

      applyThemeToPanel(div, this.userTheme);
      div.style.padding = '10px';
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

      // Since user clicked to open panel, make it visible and update localStorage
      div.style.display = 'block';
      localStorage.setItem('mapPanelOpen', 'true');

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

    const timezone = this.timezone || 'UTC';
    const html = citiesData.map(country => `
      <div class="mb-4" style="min-width: min-content;">
        <h4 class="font-bold text-md">${country.country}</h4>
        <ul class="ml-4 space-y-1">
          ${country.cities.map(city => `
            <li class="text-sm whitespace-nowrap">
              ${city.city}
              <span class="text-gray-500">
                (${new Date(city.timestamp * 1000).toLocaleDateString('en-US', { timeZone: timezone })})
              </span>
            </li>
          `).join('')}
        </ul>
      </div>
    `).join('');

    container.innerHTML = html;
  }

  showGradientEditor() {
    const modal = document.createElement("div");
    modal.id = "gradient-editor-modal";
    Object.assign(modal.style, {
      position: "fixed",
      top: "0",
      left: "0",
      right: "0",
      bottom: "0",
      backgroundColor: "rgba(0, 0, 0, 0.5)",
      display: "flex",
      justifyContent: "center",
      alignItems: "center",
      zIndex: "100",
    });

    const content = document.createElement("div");
    Object.assign(content.style, {
      backgroundColor: "#fff",
      padding: "20px",
      borderRadius: "5px",
      minWidth: "300px",
      maxHeight: "80vh",
      display: "flex",
      flexDirection: "column",
    });

    const title = document.createElement("h2");
    title.textContent = "Edit Speed Color Scale";
    content.appendChild(title);

    const gradientContainer = document.createElement("div");
    gradientContainer.id = "gradient-editor-container";
    Object.assign(gradientContainer.style, {
      marginTop: "15px",
      overflowY: "auto",
      flex: "1",
      border: "1px solid #ccc",
      padding: "5px",
    });

    const createRow = (stop = { speed: 0, color: "#000000" }) => {
      const row = document.createElement("div");
      row.style.display = "flex";
      row.style.alignItems = "center";
      row.style.gap = "10px";
      row.style.marginBottom = "8px";

      const speedInput = document.createElement("input");
      speedInput.type = "number";
      speedInput.value = stop.speed;
      speedInput.style.width = "70px";

      const colorInput = document.createElement("input");
      colorInput.type = "color";
      colorInput.value = stop.color;
      colorInput.style.width = "70px";

      const removeBtn = document.createElement("button");
      removeBtn.textContent = "x";
      removeBtn.style.color = "#cc3311";
      removeBtn.style.flexShrink = "0";
      removeBtn.addEventListener("click", () => {
        if (gradientContainer.childElementCount > 1) {
          gradientContainer.removeChild(row);
        } else {
          showFlashMessage('error', 'At least one gradient stop is required.');
        }
      });

      row.appendChild(speedInput);
      row.appendChild(colorInput);
      row.appendChild(removeBtn);
      return row;
    };

    let stops;
    try {
      stops = colorFormatDecode(this.speedColorScale);
    } catch (error) {
      stops = colorStopsFallback;
    }
    stops.forEach(stop => {
      const row = createRow(stop);
      gradientContainer.appendChild(row);
    });

    content.appendChild(gradientContainer);

    const addRowBtn = document.createElement("button");
    addRowBtn.textContent = "Add Row";
    addRowBtn.style.marginTop = "10px";
    addRowBtn.addEventListener("click", () => {
      const newRow = createRow({ speed: 0, color: "#000000" });
      gradientContainer.appendChild(newRow);
    });
    content.appendChild(addRowBtn);

    const btnContainer = document.createElement("div");
    btnContainer.style.display = "flex";
    btnContainer.style.justifyContent = "flex-end";
    btnContainer.style.gap = "10px";
    btnContainer.style.marginTop = "15px";

    const cancelBtn = document.createElement("button");
    cancelBtn.textContent = "Cancel";
    cancelBtn.addEventListener("click", () => {
      document.body.removeChild(modal);
    });

    const saveBtn = document.createElement("button");
    saveBtn.textContent = "Save";
    saveBtn.addEventListener("click", () => {
      const newStops = [];
      gradientContainer.querySelectorAll("div").forEach(row => {
        const inputs = row.querySelectorAll("input");
        const speed = Number(inputs[0].value);
        const color = inputs[1].value;
        newStops.push({ speed, color });
      });

      const newGradient = colorFormatEncode(newStops);

      this.speedColorScale = newGradient;
      const speedColorScaleInput = document.getElementById("speed_color_scale");
      if (speedColorScaleInput) {
        speedColorScaleInput.value = newGradient;
      }

      document.body.removeChild(modal);
    });

    btnContainer.appendChild(cancelBtn);
    btnContainer.appendChild(saveBtn);
    content.appendChild(btnContainer);
    modal.appendChild(content);
    document.body.appendChild(modal);
  }

  // Track-related methods
  async initializeTracksLayer() {
    // Use pre-loaded tracks data if available
    if (this.tracksData && this.tracksData.length > 0) {
      this.createTracksFromData(this.tracksData);
    } else {
      // Create empty layer for layer control
      this.tracksLayer = L.layerGroup();
    }
  }

  createTracksFromData(tracksData) {
    // Clear existing tracks
    this.tracksLayer.clearLayers();

    if (!tracksData || tracksData.length === 0) {
      return;
    }

    // Create tracks layer with data and add to existing tracks layer
    const newTracksLayer = createTracksLayer(
      tracksData,
      this.map,
      this.userSettings,
      this.distanceUnit
    );

    // Add all tracks to the existing tracks layer
    newTracksLayer.eachLayer((layer) => {
      this.tracksLayer.addLayer(layer);
    });
  }

  toggleTracksVisibility(event) {
    this.tracksVisible = event.target.checked;

    if (this.tracksLayer) {
      toggleTracksVisibility(this.tracksLayer, this.map, this.tracksVisible);
    }
  }

  initializeLocationSearch() {
    if (this.map && this.apiKey && this.features.reverse_geocoding) {
      this.locationSearch = new LocationSearch(this.map, this.apiKey, this.userTheme);
    }
  }

  // Helper method for family controller to update layer control
  updateLayerControl(additionalLayers = {}) {
    if (!this.layerControl) return;

    // Remove existing layer control
    this.map.removeControl(this.layerControl);

    // Re-add the layer control with additional layers
    this.layerControl = this.createTreeLayerControl(additionalLayers);
    this.map.addControl(this.layerControl);
  }

  togglePlaceCreationMode() {
    if (!this.placesManager) {
      console.warn("Places manager not initialized");
      return;
    }

    const button = document.getElementById('create-place-btn');

    if (this.placesManager.creationMode) {
      // Disable creation mode
      this.placesManager.disableCreationMode();
      if (button) {
        setCreatePlaceButtonInactive(button, this.userTheme);
        button.setAttribute('data-tip', 'Create a place');
      }
    } else {
      // Enable creation mode
      this.placesManager.enableCreationMode();
      if (button) {
        setCreatePlaceButtonActive(button);
        button.setAttribute('data-tip', 'Click map to place marker (click to cancel)');
      }
    }
  }

  disablePlaceCreationMode() {
    if (!this.placesManager) {
      return;
    }

    // Only disable if currently in creation mode
    if (this.placesManager.creationMode) {
      this.placesManager.disableCreationMode();

      const button = document.getElementById('create-place-btn');
      if (button) {
        setCreatePlaceButtonInactive(button, this.userTheme);
        button.setAttribute('data-tip', 'Create a place');
      }
    }
  }

  async initializePrivacyZones() {
    try {
      await this.privacyZoneManager.loadPrivacyZones();

      if (this.privacyZoneManager.hasPrivacyZones()) {
        console.log(`[Privacy Zones] Loaded ${this.privacyZoneManager.getZoneCount()} zones covering ${this.privacyZoneManager.getTotalPlacesCount()} places`);

        // Apply filtering to markers BEFORE they're rendered
        this.markers = this.privacyZoneManager.filterPoints(this.markers);

        // Apply filtering to tracks if they exist
        if (this.tracksData && Array.isArray(this.tracksData)) {
          this.tracksData = this.privacyZoneManager.filterTracks(this.tracksData);
        }
      }
    } catch (error) {
      console.error('[Privacy Zones] Error initializing privacy zones:', error);
    }
  }
}
