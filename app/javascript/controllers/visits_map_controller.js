import BaseController from "./base_controller"
import L from "leaflet"
import { osmMapLayer } from "../maps/layers"

export default class extends BaseController {
  static targets = ["container"]

  connect() {
    this.initializeMap();
    this.visits = new Map();
    this.highlightedVisit = null;
  }

  initializeMap() {
    // Initialize the map with a default center (will be updated when visits are added)
    this.map = L.map(this.containerTarget).setView([0, 0], 2);
    osmMapLayer(this.map, "OpenStreetMap");

    // Add all visits to the map
    const visitElements = document.querySelectorAll('[data-visit-id]');
    if (visitElements.length > 0) {
      const bounds = L.latLngBounds([]);

      visitElements.forEach(element => {
        const visitId = element.dataset.visitId;
        const lat = parseFloat(element.dataset.centerLat);
        const lon = parseFloat(element.dataset.centerLon);

        if (!isNaN(lat) && !isNaN(lon)) {
          const marker = L.circleMarker([lat, lon], {
            radius: 8,
            fillColor: this.getVisitColor(element),
            color: '#fff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.8
          }).addTo(this.map);

          // Store the marker reference
          this.visits.set(visitId, {
            marker,
            element
          });

          bounds.extend([lat, lon]);
        }
      });

      // Fit the map to show all visits
      if (!bounds.isEmpty()) {
        this.map.fitBounds(bounds, {
          padding: [50, 50]
        });
      }
    }
  }

  getVisitColor(element) {
    // Check if the visit has a status badge
    const badge = element.querySelector('.badge');
    if (badge) {
      if (badge.classList.contains('badge-success')) {
        return '#2ecc71'; // Green for confirmed
      } else if (badge.classList.contains('badge-warning')) {
        return '#f1c40f'; // Yellow for suggested
      }
    }
    return '#e74c3c'; // Red for declined or unknown
  }

  highlightVisit(event) {
    const visitId = event.currentTarget.dataset.visitId;
    const visit = this.visits.get(visitId);

    if (visit) {
      // Reset previous highlight if any
      if (this.highlightedVisit) {
        this.highlightedVisit.marker.setStyle({
          radius: 8,
          fillOpacity: 0.8
        });
      }

      // Highlight the current visit
      visit.marker.setStyle({
        radius: 12,
        fillOpacity: 1
      });
      visit.marker.bringToFront();

      // Center the map on the visit
      this.map.panTo(visit.marker.getLatLng());

      this.highlightedVisit = visit;
    }
  }

  unhighlightVisit(event) {
    const visitId = event.currentTarget.dataset.visitId;
    const visit = this.visits.get(visitId);

    if (visit && this.highlightedVisit === visit) {
      visit.marker.setStyle({
        radius: 8,
        fillOpacity: 0.8
      });
      this.highlightedVisit = null;
    }
  }
}
