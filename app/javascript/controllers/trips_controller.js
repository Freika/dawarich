// This controller is being used on:
// - trips/show
// - trips/edit
// - trips/new

import BaseController from "./base_controller"
import L from "leaflet"
import {
  osmMapLayer,
  osmHotMapLayer,
  OPNVMapLayer,
  openTopoMapLayer,
  cyclOsmMapLayer,
  esriWorldStreetMapLayer,
  esriWorldTopoMapLayer,
  esriWorldImageryMapLayer,
  esriWorldGrayCanvasMapLayer
} from "../maps/layers"
import { createPopupContent } from "../maps/popups"
import {
  fetchAndDisplayPhotos,
  showFlashMessage
} from '../maps/helpers';

export default class extends BaseController {
  static targets = ["container", "startedAt", "endedAt"]
  static values = { }

  connect() {
    if (!this.hasContainerTarget) {
      return;
    }

    console.log("Trips controller connected")

    this.apiKey = this.containerTarget.dataset.api_key
    this.userSettings = JSON.parse(this.containerTarget.dataset.user_settings || '{}')
    this.timezone = this.containerTarget.dataset.timezone
    this.distanceUnit = this.containerTarget.dataset.distance_unit

    // Initialize map and layers
    this.initializeMap()

    // Add event listener for coordinates updates
    this.element.addEventListener('coordinates-updated', (event) => {
      this.updateMapWithCoordinates(event.detail.coordinates)
    })
  }

  // Move map initialization to separate method
  initializeMap() {
    // Initialize layer groups
    this.polylinesLayer = L.layerGroup()
    this.photoMarkers = L.layerGroup()

    // Set default center and zoom for world view
    const center = [20, 0]  // Roughly centers the world map
    const zoom = 2

    // Initialize map
    this.map = L.map(this.containerTarget).setView(center, zoom)

    // Add base map layer
    osmMapLayer(this.map, "OpenStreetMap")

    // Add scale control to bottom right
    L.control.scale({
      position: 'bottomright',
      imperial: this.distanceUnit === 'mi',
      metric: this.distanceUnit === 'km',
      maxWidth: 120
    }).addTo(this.map)

    const overlayMaps = {
      "Route": this.polylinesLayer,
      "Photos": this.photoMarkers
    }

    // Add layer control
    L.control.layers(this.baseMaps(), overlayMaps).addTo(this.map)

    // Add event listener for layer changes
    this.map.on('overlayadd', (e) => {
      if (e.name !== 'Photos') return;

      const startedAt = this.element.dataset.started_at;
      const endedAt = this.element.dataset.ended_at;

      console.log('Dataset values:', {
        startedAt,
        endedAt,
        path: this.element.dataset.path
      });

      if ((!this.userSettings.immich_url || !this.userSettings.immich_api_key) && (!this.userSettings.photoprism_url || !this.userSettings.photoprism_api_key)) {
        showFlashMessage(
          'error',
          'Photos integration is not configured. Please check your integrations settings.'
        );
        return;
      }

      // Try to get dates from coordinates first, then fall back to path data
      let startDate, endDate;

      if (this.coordinates?.length) {
        const firstCoord = this.coordinates[0];
        const lastCoord = this.coordinates[this.coordinates.length - 1];
        startDate = new Date(firstCoord[4] * 1000).toISOString().split('T')[0];
        endDate = new Date(lastCoord[4] * 1000).toISOString().split('T')[0];
      } else if (startedAt && endedAt) {
        // Parse the dates and format them correctly
        startDate = new Date(startedAt).toISOString().split('T')[0];
        endDate = new Date(endedAt).toISOString().split('T')[0];
      } else {
        console.log('No date range available for photos');
        showFlashMessage(
          'error',
          'No date range available for photos. Please ensure the trip has start and end dates.'
        );
        return;
      }

      fetchAndDisplayPhotos({
        map: this.map,
        photoMarkers: this.photoMarkers,
        apiKey: this.apiKey,
        startDate: startDate,
        endDate: endDate,
        userSettings: this.userSettings
      });
    });

    // Add markers and route
    if (this.coordinates?.length > 0) {
      this.addMarkers()
      this.addPolyline()
      this.fitMapToBounds()
    }

    // After map initialization, add the path if it exists
    if (this.containerTarget.dataset.path) {
      const pathData = this.containerTarget.dataset.path.replace(/^"|"$/g, ''); // Remove surrounding quotes
      const coordinates = this.parseLineString(pathData);

      const polyline = L.polyline(coordinates, {
        color: 'blue',
        opacity: 0.8,
        weight: 3,
        zIndexOffset: 400
      });

      polyline.addTo(this.polylinesLayer);
      this.polylinesLayer.addTo(this.map);

      // Fit the map to the polyline bounds
      if (coordinates.length > 0) {
        this.map.fitBounds(polyline.getBounds(), { padding: [50, 50] });
      }
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
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

  addMarkers() {
    this.coordinates.forEach(coord => {
      const marker = L.circleMarker(
        [coord[0], coord[1]],
        {
          radius: 4,
          color: coord[5] < 0 ? "orange" : "blue",
          zIndexOffset: 1000
        }
      )

      const popupContent = createPopupContent(coord, this.timezone, this.distanceUnit)
      marker.bindPopup(popupContent)
      marker.addTo(this.polylinesLayer)
    })
  }

  addPolyline() {
    const points = this.coordinates.map(coord => [coord[0], coord[1]])
    const polyline = L.polyline(points, {
      color: 'blue',
      opacity: 0.8,
      weight: 3,
      zIndexOffset: 400
    })
    // Add to polylines layer instead of directly to map
    this.polylinesLayer.addTo(this.map)
    polyline.addTo(this.polylinesLayer)
  }

  fitMapToBounds() {
    const bounds = L.latLngBounds(
      this.coordinates.map(coord => [coord[0], coord[1]])
    )
    this.map.fitBounds(bounds, { padding: [50, 50] })
  }

  // Update coordinates and refresh the map
  updateMapWithCoordinates(newCoordinates) {
    // Transform the coordinates to match the expected format
    this.coordinates = newCoordinates.map(point => [
      parseFloat(point.latitude),
      parseFloat(point.longitude),
      point.id,
      null, // This is so we can use the same order and position of elements in the coordinates object as in the api/v1/points response
      (point.timestamp).toString()
    ]).sort((a, b) => a[4] - b[4]);

    // Clear existing layers
    this.polylinesLayer.clearLayers()
    this.photoMarkers.clearLayers()

    // Add new markers and route if coordinates exist
    if (this.coordinates?.length > 0) {
      this.addMarkers()
      this.addPolyline()
      this.fitMapToBounds()
    }
  }

  // Add this method to parse the LineString format
  parseLineString(lineString) {
    // Remove LINESTRING and parentheses, then split into coordinate pairs
    const coordsString = lineString.replace('LINESTRING (', '').replace(')', '');
    const coords = coordsString.split(', ');

    // Convert each coordinate pair to [lat, lng] format
    return coords.map(coord => {
      const [lng, lat] = coord.split(' ').map(Number);
      return [lat, lng]; // Swap to lat, lng for Leaflet
    });
  }
}
