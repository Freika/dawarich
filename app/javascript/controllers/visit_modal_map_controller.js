import { Controller } from "@hotwired/stimulus"
import L, { latLng } from "leaflet";
import { osmMapLayer } from "../maps/layers";

// Connects to data-controller="visit-modal-map"
export default class extends Controller {
  static targets = ["container"];

  connect() {
    console.log("Visits maps controller connected");
    this.coordinates = JSON.parse(this.element.dataset.coordinates);
    this.center = JSON.parse(this.element.dataset.center);
    this.radius = this.element.dataset.radius;
    this.map = L.map(this.containerTarget).setView([this.center[0], this.center[1]], 17);

    osmMapLayer(this.map),
    this.addMarkers();

    L.circle([this.center[0], this.center[1]], {
      radius: this.radius,
      color: 'red',
      fillColor: '#f03',
      fillOpacity: 0.5
    }).addTo(this.map);
  }

  addMarkers() {
    this.coordinates.forEach((coordinate) => {
      L.circleMarker([coordinate[0], coordinate[1]], { radius: 4 }).addTo(this.map);
    });
  }
}
