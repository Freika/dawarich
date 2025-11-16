// Maps Places Layer Manager
// Handles displaying user places with tag icons and colors on the map

import L from 'leaflet';

export class PlacesManager {
  constructor(map, apiKey) {
    this.map = map;
    this.apiKey = apiKey;
    this.placesLayer = null;
    this.places = [];
    this.markers = {};
    this.selectedTags = new Set();
    this.creationMode = false;
    this.creationMarker = null;
  }

  async initialize() {
    this.placesLayer = L.layerGroup().addTo(this.map);
    await this.loadPlaces();
    this.setupMapClickHandler();
  }

  async loadPlaces(tagIds = null) {
    try {
      const url = new URL('/api/v1/places', window.location.origin);
      if (tagIds && tagIds.length > 0) {
        tagIds.forEach(id => url.searchParams.append('tag_ids[]', id));
      }

      const response = await fetch(url, {
        headers: { 'APIKEY': this.apiKey }
      });

      if (!response.ok) throw new Error('Failed to load places');

      this.places = await response.json();
      this.renderPlaces();
    } catch (error) {
      console.error('Error loading places:', error);
    }
  }

  renderPlaces() {
    // Clear existing markers
    this.placesLayer.clearLayers();
    this.markers = {};

    this.places.forEach(place => {
      const marker = this.createPlaceMarker(place);
      if (marker) {
        this.markers[place.id] = marker;
        marker.addTo(this.placesLayer);
      }
    });
  }

  createPlaceMarker(place) {
    if (!place.latitude || !place.longitude) return null;

    const icon = this.createPlaceIcon(place);
    const marker = L.marker([place.latitude, place.longitude], { icon });

    const popupContent = this.createPopupContent(place);
    marker.bindPopup(popupContent);

    return marker;
  }

  createPlaceIcon(place) {
    const emoji = place.icon || place.tags[0]?.icon || '📍';
    const color = place.color || place.tags[0]?.color || '#4CAF50';

    const iconHtml = `
      <div class="place-marker" style="
        background-color: ${color};
        width: 32px;
        height: 32px;
        border-radius: 50% 50% 50% 0;
        border: 2px solid white;
        display: flex;
        align-items: center;
        justify-content: center;
        transform: rotate(-45deg);
        box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      ">
        <span style="transform: rotate(45deg); font-size: 16px;">${emoji}</span>
      </div>
    `;

    return L.divIcon({
      html: iconHtml,
      className: 'place-icon',
      iconSize: [32, 32],
      iconAnchor: [16, 32],
      popupAnchor: [0, -32]
    });
  }

  createPopupContent(place) {
    const tags = place.tags.map(tag => 
      `<span class="badge badge-sm" style="background-color: ${tag.color}">
        ${tag.icon} ${tag.name}
      </span>`
    ).join(' ');

    return `
      <div class="place-popup" style="min-width: 200px;">
        <h3 class="font-bold text-lg mb-2">${place.name}</h3>
        ${tags ? `<div class="mb-2">${tags}</div>` : ''}
        ${place.visits_count ? `<p class="text-sm">Visits: ${place.visits_count}</p>` : ''}
        <div class="mt-2 flex gap-2">
          <button class="btn btn-xs btn-error" data-place-id="${place.id}" data-action="delete-place">
            Delete
          </button>
        </div>
      </div>
    `;
  }

  setupMapClickHandler() {
    this.map.on('click', (e) => {
      if (this.creationMode) {
        this.handleMapClick(e);
      }
    });

    // Delegate event handling for delete buttons
    this.map.on('popupopen', (e) => {
      const popup = e.popup;
      const deleteBtn = popup.getElement()?.querySelector('[data-action="delete-place"]');
      
      if (deleteBtn) {
        deleteBtn.addEventListener('click', async () => {
          const placeId = deleteBtn.dataset.placeId;
          await this.deletePlace(placeId);
          popup.remove();
        });
      }
    });
  }

  async handleMapClick(e) {
    const { lat, lng } = e.latlng;
    
    // Remove existing creation marker
    if (this.creationMarker) {
      this.map.removeLayer(this.creationMarker);
    }

    // Add temporary marker
    this.creationMarker = L.marker([lat, lng], {
      icon: this.createPlaceIcon({ icon: '📍', color: '#FF9800' })
    }).addTo(this.map);

    // Trigger place creation modal
    this.triggerPlaceCreation(lat, lng);
  }

  async triggerPlaceCreation(lat, lng) {
    const event = new CustomEvent('place:create', {
      detail: { latitude: lat, longitude: lng },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  async deletePlace(placeId) {
    if (!confirm('Are you sure you want to delete this place?')) return;

    try {
      const response = await fetch(`/api/v1/places/${placeId}`, {
        method: 'DELETE',
        headers: { 'APIKEY': this.apiKey }
      });

      if (!response.ok) throw new Error('Failed to delete place');

      // Remove marker and reload
      if (this.markers[placeId]) {
        this.placesLayer.removeLayer(this.markers[placeId]);
        delete this.markers[placeId];
      }

      this.places = this.places.filter(p => p.id !== parseInt(placeId));
      
      this.showNotification('Place deleted successfully', 'success');
    } catch (error) {
      console.error('Error deleting place:', error);
      this.showNotification('Failed to delete place', 'error');
    }
  }

  enableCreationMode() {
    this.creationMode = true;
    this.map.getContainer().style.cursor = 'crosshair';
    this.showNotification('Click on the map to add a place', 'info');
  }

  disableCreationMode() {
    this.creationMode = false;
    this.map.getContainer().style.cursor = '';
    
    if (this.creationMarker) {
      this.map.removeLayer(this.creationMarker);
      this.creationMarker = null;
    }
  }

  filterByTags(tagIds) {
    this.selectedTags = new Set(tagIds);
    this.loadPlaces(tagIds.length > 0 ? tagIds : null);
  }

  async refreshPlaces() {
    const tagIds = this.selectedTags.size > 0 ? Array.from(this.selectedTags) : null;
    await this.loadPlaces(tagIds);
  }

  show() {
    if (this.placesLayer) {
      this.map.addLayer(this.placesLayer);
    }
  }

  hide() {
    if (this.placesLayer) {
      this.map.removeLayer(this.placesLayer);
    }
  }

  showNotification(message, type = 'info') {
    const event = new CustomEvent('notification:show', {
      detail: { message, type },
      bubbles: true
    });
    document.dispatchEvent(event);
  }
}
