import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    console.log("Map controller connected")
    var markers = JSON.parse(this.element.dataset.coordinates)
    var center = markers[0]
    var center = (center === undefined) ? [52.516667, 13.383333] : center;
    var map = L.map(this.containerTarget).setView(center, 14);

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);

    for (var i = 0; i < markers.length; i++) {

      var lat = markers[i][0];
      var lon = markers[i][1];

      L.circleMarker([lat, lon], {radius: 3}).addTo(map);
    }

    L.polyline(markers).addTo(map);
  }

  disconnect() {
    this.map.remove();
  }
}
