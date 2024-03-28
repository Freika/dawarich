import { Controller } from "@hotwired/stimulus"
import L, { circleMarker } from "leaflet"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    console.log("Map controller connected")
    var markers = JSON.parse(this.element.dataset.coordinates)
    var center = markers[0] || JSON.parse(this.element.dataset.center)
    var center = (center === undefined) ? [52.516667, 13.383333] : center;
    var map = L.map(this.containerTarget).setView([center[0], center[1]], 14);

    this.addTileLayer(map);
    this.addMarkers(map, markers);
    this.addPolyline(map, markers);
    this.addLastMarker(map, markers);
  }

  disconnect() {
    this.map.remove();
  }

  popupContent(marker) {
    return `
      <b>Timestamp:</b> ${this.formatDate(marker[4])}<br>
      <b>Latitude:</b> ${marker[0]}<br>
      <b>Longitude:</b> ${marker[1]}<br>
      <b>Altitude:</b> ${marker[3]}m<br>
      <b>Velocity:</b> ${marker[5]}km/h<br>
      <b>Battery:</b> ${marker[2]}%
    `;
  }

  formatDate(timestamp) {
    let date = new Date(timestamp * 1000); // Multiply by 1000 because JavaScript works with milliseconds

    // Extracting date components
    let year = date.getFullYear();
    let month = ('0' + (date.getMonth() + 1)).slice(-2); // Adding 1 because getMonth() returns zero-based month
    let day = ('0' + date.getDate()).slice(-2);
    let hours = ('0' + date.getHours()).slice(-2);
    let minutes = ('0' + date.getMinutes()).slice(-2);
    let seconds = ('0' + date.getSeconds()).slice(-2);

    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  addTileLayer(map) {
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);
  }

  addMarkers(map, markers_data) {
    var markers = []
    for (var i = 0; i < markers_data.length; i++) {
      var lat = markers_data[i][0];
      var lon = markers_data[i][1];

      var popupContent = this.popupContent(markers_data[i]);
      var circleMarker = L.circleMarker([lat, lon], {radius: 4})

      markers.push(circleMarker.bindPopup(popupContent).openPopup())
    }

    L.layerGroup(markers).addTo(map);
  }

  addPolyline(map, markers) {
    var coordinates = markers.map(element => element.slice(0, 2));
    L.polyline(coordinates).addTo(map);
  }

  addLastMarker(map, markers) {
    if (markers.length > 0) {
      var lastMarker = markers[markers.length - 1].slice(0, 2)
      L.marker(lastMarker).addTo(map);
    }
  }
}
