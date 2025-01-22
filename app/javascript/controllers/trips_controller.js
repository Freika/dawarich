import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import { osmMapLayer } from "../maps/layers"
import { createPopupContent } from "../maps/popups"
import { osmHotMapLayer } from "../maps/layers"
import { OPNVMapLayer } from "../maps/layers"
import { openTopoMapLayer } from "../maps/layers"
import { cyclOsmMapLayer } from "../maps/layers"
import { esriWorldStreetMapLayer } from "../maps/layers"
import { esriWorldTopoMapLayer } from "../maps/layers"
import { esriWorldImageryMapLayer } from "../maps/layers"
import { esriWorldGrayCanvasMapLayer } from "../maps/layers"
import { fetchAndDisplayPhotos } from '../maps/helpers';
import { showFlashMessage } from "../maps/helpers";

export default class extends Controller {
  static targets = ["container", "startedAt", "endedAt"]
  static values = { }

  connect() {
    if (!this.hasContainerTarget) {
      return;
    }

    console.log("Trips controller connected")
    this.coordinates = JSON.parse(this.containerTarget.dataset.coordinates)
    this.apiKey = this.containerTarget.dataset.api_key
    this.userSettings = JSON.parse(this.containerTarget.dataset.user_settings)
    this.timezone = this.containerTarget.dataset.timezone
    this.distanceUnit = this.containerTarget.dataset.distance_unit

    // Initialize map and layers
    this.initializeMap()

    // Add event listener for coordinates updates
    this.element.addEventListener('coordinates-updated', (event) => {
      console.log("Coordinates updated:", event.detail.coordinates)
      this.updateMapWithCoordinates(event.detail.coordinates)
    })
  }

  // Move map initialization to separate method
  initializeMap() {
    // Initialize layer groups
    this.markersLayer = L.layerGroup()
    this.polylinesLayer = L.layerGroup()
    this.photoMarkers = L.layerGroup()

    // Set default center and zoom for world view
    const hasValidCoordinates = this.coordinates && Array.isArray(this.coordinates) && this.coordinates.length > 0
    const center = hasValidCoordinates
      ? [this.coordinates[0][0], this.coordinates[0][1]]
      : [20, 0]  // Roughly centers the world map
    const zoom = hasValidCoordinates ? 14 : 2

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
      "Points": this.markersLayer,
      "Route": this.polylinesLayer,
      "Photos": this.photoMarkers
    }

    // Add layer control
    L.control.layers(this.baseMaps(), overlayMaps).addTo(this.map)

    // Add event listener for layer changes
    this.map.on('overlayadd', (e) => {
      if (e.name !== 'Photos') return;

      if ((!this.userSettings.immich_url || !this.userSettings.immich_api_key) && (!this.userSettings.photoprism_url || !this.userSettings.photoprism_api_key)) {
        showFlashMessage(
          'error',
          'Photos integration is not configured. Please check your integrations settings.'
        );
        return;
      }

      if (!this.coordinates?.length) return;

      const firstCoord = this.coordinates[0];
      const lastCoord = this.coordinates[this.coordinates.length - 1];

      const startDate = new Date(firstCoord[4] * 1000).toISOString().split('T')[0];
      const endDate = new Date(lastCoord[4] * 1000).toISOString().split('T')[0];

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

      // Add to markers layer instead of directly to map
      marker.addTo(this.markersLayer)
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

  // Add this new method to update coordinates and refresh the map
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
    this.markersLayer.clearLayers()
    this.polylinesLayer.clearLayers()
    this.photoMarkers.clearLayers()

    // Add new markers and route if coordinates exist
    if (this.coordinates?.length > 0) {
      this.addMarkers()
      this.addPolyline()
      this.fitMapToBounds()
    }
  }
}
