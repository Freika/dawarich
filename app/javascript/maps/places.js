// Maps Places Layer Manager
// Handles displaying user places with tag icons and colors on the map

import L from 'leaflet';
import { showFlashMessage } from './helpers';

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
    this.placesLayer = L.layerGroup();

    // Add event listener to reload places when layer is added to map
    this.placesLayer.on('add', () => {
      this.loadPlaces();
    });

    console.log("[PlacesManager] Initializing, loading places for first time...");
    await this.loadPlaces();
    this.setupMapClickHandler();
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Refresh places when a new place is created
    document.addEventListener('place:created', async (event) => {
      const { place } = event.detail;

      // Show success message
      showFlashMessage('success', `Place "${place.name}" created successfully!`);

      // Add the new place to the main places layer
      await this.refreshPlaces();

      // Refresh all filtered layers that are currently on the map
      this.map.eachLayer((layer) => {
        if (layer._tagIds !== undefined) {
          // This is a filtered layer, reload it
          this.loadPlacesIntoLayer(layer, layer._tagIds);
        }
      });

      // Ensure the main Places layer is visible
      this.ensurePlacesLayerVisible();
    });
  }

  async loadPlaces(tagIds = null) {
    try {
      const url = new URL('/api/v1/places', window.location.origin);
      if (tagIds && tagIds.length > 0) {
        tagIds.forEach(id => url.searchParams.append('tag_ids[]', id));
      }

      console.log("[PlacesManager] loadPlaces called, fetching from:", url.toString());
      const response = await fetch(url, {
        headers: { 'Authorization': `Bearer ${this.apiKey}` }
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
    const marker = L.marker([place.latitude, place.longitude], { icon, placeId: place.id });

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
        ${tag.icon} #${tag.name}
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
        headers: { 'Authorization': `Bearer ${this.apiKey}` }
      });

      if (!response.ok) throw new Error('Failed to delete place');

      // Remove marker from main layer
      if (this.markers[placeId]) {
        this.placesLayer.removeLayer(this.markers[placeId]);
        delete this.markers[placeId];
      }

      // Remove from all layers on the map (including filtered layers)
      this.map.eachLayer((layer) => {
        if (layer instanceof L.LayerGroup) {
          layer.eachLayer((marker) => {
            if (marker.options && marker.options.placeId === parseInt(placeId)) {
              layer.removeLayer(marker);
            }
          });
        }
      });

      // Remove from places array
      this.places = this.places.filter(p => p.id !== parseInt(placeId));
      
      showFlashMessage('success', 'Place deleted successfully');
    } catch (error) {
      console.error('Error deleting place:', error);
      showFlashMessage('error', 'Failed to delete place');
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

  /**
   * Create a filtered layer for tree control
   * Returns a layer group that will be populated with filtered places
   */
  createFilteredLayer(tagIds) {
    const filteredLayer = L.layerGroup();

    // Store tag IDs for this layer
    filteredLayer._tagIds = tagIds;

    // Add event listener to load places when layer is added to map
    filteredLayer.on('add', () => {
      console.log(`[PlacesManager] Filtered layer added to map, tagIds:`, tagIds);
      this.loadPlacesIntoLayer(filteredLayer, tagIds);
    });

    console.log(`[PlacesManager] Created filtered layer for tagIds:`, tagIds);
    return filteredLayer;
  }

  /**
   * Load places into a specific layer with tag filtering
   */
  async loadPlacesIntoLayer(layer, tagIds) {
    try {
      console.log(`[PlacesManager] loadPlacesIntoLayer called with tagIds:`, tagIds);
      let url = `/api/v1/places?api_key=${this.apiKey}`;

      if (Array.isArray(tagIds) && tagIds.length > 0) {
        // Specific tags requested
        url += `&tag_ids=${tagIds.join(',')}`;
      } else if (Array.isArray(tagIds) && tagIds.length === 0) {
        // Empty array means untagged places only
        url += '&untagged=true';
      }

      console.log(`[PlacesManager] Fetching from URL:`, url);
      const response = await fetch(url);
      const data = await response.json();
      console.log(`[PlacesManager] Received ${data.length} places for tagIds:`, tagIds);

      // Clear existing markers in this layer
      layer.clearLayers();

      // Add markers to this layer
      data.forEach(place => {
        const marker = this.createPlaceMarker(place);
        layer.addLayer(marker);
      });

      console.log(`[PlacesManager] Added ${data.length} markers to layer`);
    } catch (error) {
      console.error('Error loading places into layer:', error);
    }
  }

  async refreshPlaces() {
    const tagIds = this.selectedTags.size > 0 ? Array.from(this.selectedTags) : null;
    await this.loadPlaces(tagIds);
  }

  ensurePlacesLayerVisible() {
    // Check if the main places layer is already on the map
    if (this.map.hasLayer(this.placesLayer)) {
      console.log('Places layer already visible');
      return;
    }

    // Try to find and enable the Places checkbox in the tree control
    const layerControl = document.querySelector('.leaflet-control-layers');
    if (!layerControl) {
      console.log('Layer control not found, adding places layer directly');
      this.map.addLayer(this.placesLayer);
      return;
    }

    // Find the Places checkbox and enable it
    setTimeout(() => {
      const inputs = layerControl.querySelectorAll('input[type="checkbox"]');
      inputs.forEach(input => {
        const label = input.closest('label') || input.nextElementSibling;
        if (label && label.textContent.trim() === 'Places') {
          if (!input.checked) {
            input.checked = true;
            input.dispatchEvent(new Event('change', { bubbles: true }));
            console.log('Enabled Places layer in tree control');
          }
        }
      });
    }, 100);
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
