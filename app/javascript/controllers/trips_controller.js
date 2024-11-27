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
// import { fetchAndDisplayPhotos } from "../helpers/photoFetcher";

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.coordinates = JSON.parse(this.element.dataset.coordinates)
    this.apiKey = this.element.dataset.api_key
    this.userSettings = JSON.parse(this.element.dataset.user_settings)
    this.timezone = this.element.dataset.timezone
    this.distanceUnit = this.element.dataset.distance_unit

    // Initialize layer groups
    this.markersLayer = L.layerGroup()
    this.polylinesLayer = L.layerGroup()
    this.photoMarkers = L.layerGroup()

    const center = [this.coordinates[0][0], this.coordinates[0][1]]

    // Initialize map
    this.map = L.map(this.containerTarget).setView(center, 14)

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

    // Add markers for each coordinate
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
      const marker = L.circleMarker([coord[0], coord[1]], {radius: 4})

      const popupContent = createPopupContent(coord, this.timezone, this.distanceUnit)
      marker.bindPopup(popupContent)

      // Add to markers layer instead of directly to map
      this.markersLayer.addTo(this.map)
      marker.addTo(this.markersLayer)
    })
  }

  addPolyline() {
    const points = this.coordinates.map(coord => [coord[0], coord[1]])
    const polyline = L.polyline(points, {
      color: 'blue',
      weight: 3,
      opacity: 0.6
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

  someMethod() {
    // Example usage
    const startDate = '2023-01-01';
    const endDate = '2023-12-31';
    fetchAndDisplayPhotos(this.map, this.apiKey, this.photoMarkers, startDate, endDate);
  }
}
