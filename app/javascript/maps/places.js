// Maps Places Layer Manager
// Handles displaying user places with tag icons and colors on the map

import L from 'leaflet';
import Flash from "controllers/flash_controller";

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

    await this.loadPlaces();
    this.setupMapClickHandler();
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Refresh places when a new place is created
    document.addEventListener('place:created', async (event) => {
      const { place } = event.detail;

      // Show success message
      Flash.show('success', `Place "${place.name}" created successfully!`);

      // Add the place to our local array
      this.places.push(place);

      // Create marker for the new place and add to main layer
      const marker = this.createPlaceMarker(place);
      if (marker) {
        this.markers[place.id] = marker;
        marker.addTo(this.placesLayer);
      }

      // Ensure the main Places layer is visible
      this.ensurePlacesLayerVisible();

      // Also add to any filtered layers that match this place's tags
      this.map.eachLayer((layer) => {
        if (layer._tagIds !== undefined) {
          // Check if this place's tags match this filtered layer
          const placeTagIds = place.tags.map(tag => tag.id);
          const layerTagIds = layer._tagIds;

          // If it's an untagged layer (empty array) and place has no tags
          if (layerTagIds.length === 0 && placeTagIds.length === 0) {
            const marker = this.createPlaceMarker(place);
            if (marker) layer.addLayer(marker);
          }
          // If place has any tags that match this layer's tags
          else if (placeTagIds.some(tagId => layerTagIds.includes(tagId))) {
            const marker = this.createPlaceMarker(place);
            if (marker) layer.addLayer(marker);
          }
        }
      });
    });

    // Refresh places when a place is updated
    document.addEventListener('place:updated', async (event) => {
      const { place } = event.detail;

      // Show success message
      Flash.show('success', `Place "${place.name}" updated successfully!`);

      // Update the place in our local array
      const index = this.places.findIndex(p => p.id === place.id);
      if (index !== -1) {
        this.places[index] = place;
      }

      // Remove old marker and add updated one to main layer
      if (this.markers[place.id]) {
        this.placesLayer.removeLayer(this.markers[place.id]);
      }
      const marker = this.createPlaceMarker(place);
      if (marker) {
        this.markers[place.id] = marker;
        marker.addTo(this.placesLayer);
      }

      // Update in all filtered layers
      this.map.eachLayer((layer) => {
        if (layer._tagIds !== undefined) {
          // Remove old marker from this layer
          layer.eachLayer((layerMarker) => {
            if (layerMarker.options && layerMarker.options.placeId === place.id) {
              layer.removeLayer(layerMarker);
            }
          });

          // Check if updated place should be in this layer
          const placeTagIds = place.tags.map(tag => tag.id);
          const layerTagIds = layer._tagIds;

          // If it's an untagged layer (empty array) and place has no tags
          if (layerTagIds.length === 0 && placeTagIds.length === 0) {
            const marker = this.createPlaceMarker(place);
            if (marker) layer.addLayer(marker);
          }
          // If place has any tags that match this layer's tags
          else if (placeTagIds.some(tagId => layerTagIds.includes(tagId))) {
            const marker = this.createPlaceMarker(place);
            if (marker) layer.addLayer(marker);
          }
        }
      });
    });
  }

  async loadPlaces(tagIds = null, untaggedOnly = false) {
    try {
      const url = new URL('/api/v1/places', window.location.origin);

      if (untaggedOnly) {
        // Load only untagged places
        url.searchParams.append('untagged', 'true');
      } else if (tagIds && tagIds.length > 0) {
        // Load places with specific tags
        tagIds.forEach(id => url.searchParams.append('tag_ids[]', id));
      }
      // If neither untaggedOnly nor tagIds, load all places

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
    const rawEmoji = place.icon || place.tags[0]?.icon || '📍';
    const emoji = this.escapeHtml(rawEmoji);
    const rawColor = place.color || place.tags[0]?.color || '#4CAF50';
    const color = this.sanitizeColor(rawColor);

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
    const tags = place.tags.map(tag => {
      const safeIcon = this.escapeHtml(tag.icon || '');
      const safeName = this.escapeHtml(tag.name || '');
      const safeColor = this.sanitizeColor(tag.color);
      return `<span class="badge badge-sm" style="background-color: ${safeColor}">
        ${safeIcon} #${safeName}
      </span>`;
    }).join(' ');

    const safeName = this.escapeHtml(place.name || '');
    const safeVisitsCount = place.visits_count ? parseInt(place.visits_count, 10) : 0;

    return `
      <div class="place-popup" style="min-width: 200px;">
        <h3 class="font-bold text-lg mb-2">${safeName}</h3>
        ${tags ? `<div class="mb-2">${tags}</div>` : ''}
        ${place.note ? `<p class="text-sm text-gray-600 mb-2 italic">${this.escapeHtml(place.note)}</p>` : ''}
        ${safeVisitsCount > 0 ? `<p class="text-sm">Visits: ${safeVisitsCount}</p>` : ''}
        <div class="mt-2 flex gap-2">
          <button class="btn btn-xs btn-primary" data-place-id="${place.id}" data-action="edit-place">
            Edit
          </button>
          <button class="btn btn-xs btn-error" data-place-id="${place.id}" data-action="delete-place">
            Delete
          </button>
        </div>
      </div>
    `;
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  sanitizeColor(color) {
    // Validate hex color format (#RGB or #RRGGBB)
    if (!color || typeof color !== 'string') {
      return '#4CAF50'; // Default green
    }

    const hexColorRegex = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
    if (hexColorRegex.test(color)) {
      return color;
    }

    return '#4CAF50'; // Default green for invalid colors
  }

  setupMapClickHandler() {
    this.map.on('click', (e) => {
      if (this.creationMode) {
        this.handleMapClick(e);
      }
    });

    // Delegate event handling for edit and delete buttons
    this.map.on('popupopen', (e) => {
      const popup = e.popup;
      const popupElement = popup.getElement();

      const editBtn = popupElement?.querySelector('[data-action="edit-place"]');
      const deleteBtn = popupElement?.querySelector('[data-action="delete-place"]');

      if (editBtn) {
        editBtn.addEventListener('click', () => {
          const placeId = editBtn.dataset.placeId;
          this.editPlace(placeId);
          popup.remove();
        });
      }

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

  editPlace(placeId) {
    const place = this.places.find(p => p.id === parseInt(placeId));
    if (!place) {
      console.error('Place not found:', placeId);
      return;
    }

    const event = new CustomEvent('place:edit', {
      detail: { place },
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
      
      Flash.show('success', 'Place deleted successfully');
    } catch (error) {
      console.error('Error deleting place:', error);
      Flash.show('error', 'Failed to delete place');
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

  filterByTags(tagIds, untaggedOnly = false) {
    this.selectedTags = new Set(tagIds || []);
    this.loadPlaces(tagIds && tagIds.length > 0 ? tagIds : null, untaggedOnly);
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
      this.loadPlacesIntoLayer(filteredLayer, tagIds);
    });

    return filteredLayer;
  }

  /**
   * Load places into a specific layer with tag filtering
   */
  async loadPlacesIntoLayer(layer, tagIds) {
    try {
      const url = new URL('/api/v1/places', window.location.origin);

      if (Array.isArray(tagIds) && tagIds.length > 0) {
        // Specific tags requested
        tagIds.forEach(id => url.searchParams.append('tag_ids[]', id));
      } else if (Array.isArray(tagIds) && tagIds.length === 0) {
        // Empty array means untagged places only
        url.searchParams.append('untagged', 'true');
      }

      const response = await fetch(url, {
        headers: { 'Authorization': `Bearer ${this.apiKey}` }
      });
      const data = await response.json();

      // Clear existing markers in this layer
      layer.clearLayers();

      // Add markers to this layer
      data.forEach(place => {
        const marker = this.createPlaceMarker(place);
        layer.addLayer(marker);
      });
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
      return;
    }

    // Directly add the layer to the map first for immediate visibility
    this.map.addLayer(this.placesLayer);

    // Then try to sync the checkbox in the layer control if it exists
    const layerControl = document.querySelector('.leaflet-control-layers');
    if (layerControl) {
      setTimeout(() => {
        const inputs = layerControl.querySelectorAll('input[type="checkbox"]');
        inputs.forEach(input => {
          const label = input.closest('label') || input.nextElementSibling;
          if (label && label.textContent.trim() === 'Places') {
            if (!input.checked) {
              // Set a flag to prevent saving during programmatic layer addition
              if (window.mapsController) {
                window.mapsController.isRestoringLayers = true;
              }

              input.checked = true;
              // Don't dispatch change event since we already added the layer

              // Reset the flag after a short delay
              setTimeout(() => {
                if (window.mapsController) {
                  window.mapsController.isRestoringLayers = false;
                }
              }, 50);
            }
          }
        });
      }, 100);
    }
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
    Flash.show(type, message);
  }
}
