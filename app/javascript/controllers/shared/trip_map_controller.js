import L from "leaflet";
import BaseController from "../base_controller";

export default class extends BaseController {
  static values = {
    coordinates: Array,
    name: String
  };

  connect() {
    super.connect();
    this.initializeMap();
    this.renderTripPath();
  }

  disconnect() {
    if (this.map) {
      this.map.remove();
    }
  }

  initializeMap() {
    // Initialize map with interactive controls enabled
    this.map = L.map(this.element, {
      zoomControl: true,
      scrollWheelZoom: true,
      doubleClickZoom: true,
      touchZoom: true,
      dragging: true,
      keyboard: true
    });

    // Add OpenStreetMap tile layer (free for public use)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19
    }).addTo(this.map);

    // Add scale control
    L.control.scale({
      position: 'bottomright',
      imperial: false,
      metric: true,
      maxWidth: 120
    }).addTo(this.map);

    // Default view
    this.map.setView([20, 0], 2);
  }

  renderTripPath() {
    if (!this.coordinatesValue || this.coordinatesValue.length === 0) {
      return;
    }

    // Create polyline from coordinates
    const polyline = L.polyline(this.coordinatesValue, {
      color: '#3b82f6',
      opacity: 0.8,
      weight: 3
    }).addTo(this.map);

    // Add start and end markers
    if (this.coordinatesValue.length > 0) {
      const startCoord = this.coordinatesValue[0];
      const endCoord = this.coordinatesValue[this.coordinatesValue.length - 1];

      // Start marker (green)
      L.circleMarker(startCoord, {
        radius: 8,
        fillColor: '#10b981',
        color: '#fff',
        weight: 2,
        opacity: 1,
        fillOpacity: 0.8
      }).addTo(this.map).bindPopup('<strong>Start</strong>');

      // End marker (red)
      L.circleMarker(endCoord, {
        radius: 8,
        fillColor: '#ef4444',
        color: '#fff',
        weight: 2,
        opacity: 1,
        fillOpacity: 0.8
      }).addTo(this.map).bindPopup('<strong>End</strong>');
    }

    // Fit map to polyline bounds with padding
    this.map.fitBounds(polyline.getBounds(), {
      padding: [50, 50]
    });
  }
}
