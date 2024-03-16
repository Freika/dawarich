import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    var markers = JSON.parse(this.element.dataset.coordinates)
    var map = L.map(this.containerTarget).setView(markers[0], 14);

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);

    for (var i = 0; i < markers.length; i++) {

      var lat = markers[i][0];
      var lon = markers[i][1];

      L.marker([lat, lon]).addTo(map);
    }

    L.polyline(markers).addTo(map);
  }

  disconnect() {
    this.map.remove();
  }
}
