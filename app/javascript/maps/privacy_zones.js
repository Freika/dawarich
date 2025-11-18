// Privacy Zones Manager
// Handles filtering of map data (points, tracks) based on privacy zones defined by tags

import L from 'leaflet';
import { haversineDistance } from './helpers';

export class PrivacyZoneManager {
  constructor(map, apiKey) {
    this.map = map;
    this.apiKey = apiKey;
    this.zones = [];
    this.visualLayers = L.layerGroup();
    this.showCircles = false;
  }

  async loadPrivacyZones() {
    try {
      const response = await fetch('/api/v1/tags/privacy_zones', {
        headers: { 'Authorization': `Bearer ${this.apiKey}` }
      });

      if (!response.ok) {
        console.warn('Failed to load privacy zones:', response.status);
        return;
      }

      this.zones = await response.json();
      console.log(`[PrivacyZones] Loaded ${this.zones.length} privacy zones`);
    } catch (error) {
      console.error('Error loading privacy zones:', error);
      this.zones = [];
    }
  }

  isPointInPrivacyZone(lat, lng) {
    if (!this.zones || this.zones.length === 0) return false;

    return this.zones.some(zone =>
      zone.places.some(place => {
        const distanceKm = haversineDistance(lat, lng, place.latitude, place.longitude);
        const distanceMeters = distanceKm * 1000;
        return distanceMeters <= zone.radius_meters;
      })
    );
  }

  filterPoints(points) {
    if (!this.zones || this.zones.length === 0) return points;

    // Filter points and ensure polylines break at privacy zone boundaries
    // We need to manipulate timestamps to force polyline breaks
    const filteredPoints = [];
    let lastWasPrivate = false;
    let privacyZoneEncountered = false;

    for (let i = 0; i < points.length; i++) {
      const point = points[i];
      const lat = point[0];
      const lng = point[1];
      const isPrivate = this.isPointInPrivacyZone(lat, lng);

      if (!isPrivate) {
        // Point is not in privacy zone, include it
        const newPoint = [...point]; // Clone the point array

        // If we just exited a privacy zone, force a polyline break by adding
        // a large time gap that exceeds minutes_between_routes threshold
        if (privacyZoneEncountered && filteredPoints.length > 0) {
          // Add 2 hours (120 minutes) to timestamp to force a break
          // This is larger than default minutes_between_routes (30 min)
          const lastPoint = filteredPoints[filteredPoints.length - 1];
          if (newPoint[4]) { // If timestamp exists (index 4)
            newPoint[4] = lastPoint[4] + (120 * 60); // Add 120 minutes in seconds
          }
          privacyZoneEncountered = false;
        }

        filteredPoints.push(newPoint);
        lastWasPrivate = false;
      } else {
        // Point is in privacy zone - skip it
        if (!lastWasPrivate) {
          privacyZoneEncountered = true;
        }
        lastWasPrivate = true;
      }
    }

    return filteredPoints;
  }

  filterTracks(tracks) {
    if (!this.zones || this.zones.length === 0) return tracks;

    return tracks.map(track => {
      const filteredPoints = track.points.filter(point => {
        const lat = point[0];
        const lng = point[1];
        return !this.isPointInPrivacyZone(lat, lng);
      });

      return {
        ...track,
        points: filteredPoints
      };
    }).filter(track => track.points.length > 0);
  }

  showPrivacyCircles() {
    this.visualLayers.clearLayers();

    if (!this.zones || this.zones.length === 0) return;

    this.zones.forEach(zone => {
      zone.places.forEach(place => {
        const circle = L.circle([place.latitude, place.longitude], {
          radius: zone.radius_meters,
          color: zone.tag_color || '#ff4444',
          fillColor: zone.tag_color || '#ff4444',
          fillOpacity: 0.1,
          dashArray: '10, 10',
          weight: 2,
          interactive: false,
          className: 'privacy-zone-circle'
        });

        // Add popup with zone info
        circle.bindPopup(`
          <div class="privacy-zone-popup">
            <strong>${zone.tag_icon || '🔒'} ${zone.tag_name}</strong><br>
            <small>${place.name}</small><br>
            <small>Privacy radius: ${zone.radius_meters}m</small>
          </div>
        `);

        circle.addTo(this.visualLayers);
      });
    });

    this.visualLayers.addTo(this.map);
    this.showCircles = true;
  }

  hidePrivacyCircles() {
    if (this.map.hasLayer(this.visualLayers)) {
      this.map.removeLayer(this.visualLayers);
    }
    this.showCircles = false;
  }

  togglePrivacyCircles(show = null) {
    const shouldShow = show !== null ? show : !this.showCircles;

    if (shouldShow) {
      this.showPrivacyCircles();
    } else {
      this.hidePrivacyCircles();
    }
  }

  hasPrivacyZones() {
    return this.zones && this.zones.length > 0;
  }

  getZoneCount() {
    return this.zones ? this.zones.length : 0;
  }

  getTotalPlacesCount() {
    if (!this.zones) return 0;
    return this.zones.reduce((sum, zone) => sum + zone.places.length, 0);
  }
}
