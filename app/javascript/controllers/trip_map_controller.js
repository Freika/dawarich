// This controller is being used on:
// - trips/index

import BaseController from "./base_controller"
import L from "leaflet"
import { createAllMapLayers } from "../maps/layers"

export default class extends BaseController {
  static values = {
    tripId: Number,
    path: String,
    apiKey: String,
    userSettings: Object,
    timezone: String,
    distanceUnit: String
  }

  connect() {
    console.log("TripMap controller connected")

    setTimeout(() => {
      this.initializeMap()
    }, 100)
  }

  initializeMap() {
    // Initialize map with basic configuration
    this.map = L.map(this.element, {
      zoomControl: false,
      dragging: false,
      scrollWheelZoom: false,
      attributionControl: true
    })

    // Add base map layer
    const selectedLayerName = this.hasUserSettingsValue ?
      this.userSettingsValue.preferred_map_layer || "OpenStreetMap" :
      "OpenStreetMap";
    const maps = this.baseMaps();
    const defaultLayer = maps[selectedLayerName] || Object.values(maps)[0];
    defaultLayer.addTo(this.map);

    // If we have coordinates, show the route
    if (this.hasPathValue && this.pathValue) {
      this.showRoute()
    } else {
      console.log("No path value available")
    }
  }

  baseMaps() {
    const selectedLayerName = this.hasUserSettingsValue ?
      this.userSettingsValue.preferred_map_layer || "OpenStreetMap" :
      "OpenStreetMap";

    let maps = createAllMapLayers(this.map, selectedLayerName, "false", 'dark');

    // Add custom map if it exists in settings
    if (this.hasUserSettingsValue && this.userSettingsValue.maps && this.userSettingsValue.maps.url) {
      const customLayer = L.tileLayer(this.userSettingsValue.maps.url, {
        maxZoom: 19,
        attribution: "&copy; OpenStreetMap contributors"
      });

      // If this is the preferred layer, add it to the map immediately
      if (selectedLayerName === this.userSettingsValue.maps.name) {
        customLayer.addTo(this.map);
        // Remove any other base layers that might be active
        Object.values(maps).forEach(layer => {
          if (this.map.hasLayer(layer)) {
            this.map.removeLayer(layer);
          }
        });
      }

      maps[this.userSettingsValue.maps.name] = customLayer;
    }

    return maps;
  }

  showRoute() {
    const points = this.getCoordinates(this.pathValue)

    // Only create polyline if we have points
    if (points.length > 0) {
      const polyline = L.polyline(points, {
        color: 'blue',
        opacity: 0.8,
        weight: 3,
        zIndexOffset: 400
      })

      // Add the polyline to the map
      polyline.addTo(this.map)

      // Fit the map bounds
      this.map.fitBounds(polyline.getBounds(), {
        padding: [20, 20]
      })
    } else {
      console.error("No valid points to create polyline")
    }
  }

  getCoordinates(pathData) {
    try {
      // Parse the path data if it's a string
      let coordinates = pathData;
      if (typeof pathData === 'string') {
        try {
          coordinates = JSON.parse(pathData);
        } catch (e) {
          console.error("Error parsing path data as JSON:", e);
          return [];
        }
      }

      // Handle array format - convert from [lng, lat] to [lat, lng] for Leaflet
      return coordinates.map(coord => {
        const [lng, lat] = coord;

        // Validate the coordinates
        if (isNaN(lat) || isNaN(lng) || !lat || !lng) {
          console.error("Invalid coordinates:", coord);
          return null;
        }

        return [lat, lng]; // Leaflet uses [lat, lng] order
      }).filter(point => point !== null);
    } catch (error) {
      console.error("Error processing coordinates:", error);
      return [];
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
    }
  }
}
