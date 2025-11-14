import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import { showFlashMessage } from "../maps/helpers";
import {
  setAddVisitButtonActive,
  setAddVisitButtonInactive
} from "../maps/map_controls";

export default class extends Controller {
  static targets = [""];
  static values = {
    apiKey: String,
    userTheme: String
  }

  connect() {
    console.log("Add visit controller connected");
    this.map = null;
    this.isAddingVisit = false;
    this.addVisitMarker = null;
    this.addVisitButton = null;
    this.currentPopup = null;
    this.mapsController = null;

    // Wait for the map to be initialized
    this.waitForMap();
  }

  disconnect() {
    this.cleanup();
    console.log("Add visit controller disconnected");
  }

  waitForMap() {
    // Get the map from the maps controller instance
    const mapElement = document.querySelector('[data-controller*="maps"]');

    if (mapElement) {
      // Try to get Stimulus controller instance
      const stimulusController = this.application.getControllerForElementAndIdentifier(mapElement, 'maps');
      if (stimulusController && stimulusController.map) {
        this.map = stimulusController.map;
        this.mapsController = stimulusController;
        this.apiKeyValue = stimulusController.apiKey;
        this.setupAddVisitButton();
        return;
      }
    }

    // Fallback: check for map container and try to find map instance
    const mapContainer = document.getElementById('map');
    if (mapContainer && mapContainer._leaflet_id) {
      // Get map instance from Leaflet registry
      this.map = window.L._getMap ? window.L._getMap(mapContainer._leaflet_id) : null;

      if (!this.map) {
        // Try through Leaflet internal registry
        const maps = window.L.Map._instances || {};
        this.map = maps[mapContainer._leaflet_id];
      }

      if (this.map) {
        // Get API key from map element data
        this.apiKeyValue = mapContainer.dataset.api_key || this.element.dataset.apiKey;
        this.setupAddVisitButton();
        return;
      }
    }

    // Wait a bit more for the map to initialize
    setTimeout(() => this.waitForMap(), 200);
  }

  setupAddVisitButton() {
    if (!this.map || this.addVisitButton) return;

    // The Add Visit button is now created centrally by maps_controller.js
    // via addTopRightButtons(). We just need to find it and attach our handler.
    setTimeout(() => {
      this.addVisitButton = document.querySelector('.add-visit-button');

      if (this.addVisitButton) {
        // Attach our click handler to the existing button
        // Use event capturing and stopPropagation to prevent map click
        this.addVisitButton.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          this.toggleAddVisitMode(this.addVisitButton);
        }, true); // Use capture phase
      } else {
        console.warn('Add visit button not found, retrying...');
        // Retry if button hasn't been created yet
        this.addVisitButton = null;
        setTimeout(() => this.setupAddVisitButton(), 200);
      }
    }, 100);
  }

  toggleAddVisitMode(button) {
    if (this.isAddingVisit) {
      // Exit add visit mode
      this.exitAddVisitMode(button);
    } else {
      // Enter add visit mode
      this.enterAddVisitMode(button);
    }
  }

  enterAddVisitMode(button) {
    this.isAddingVisit = true;

    // Update button style to show active state
    setAddVisitButtonActive(button);

    // Change cursor to crosshair
    this.map.getContainer().style.cursor = 'crosshair';

    // Add map click listener with a small delay to prevent immediate trigger
    // This ensures the button click doesn't propagate to the map
    setTimeout(() => {
      if (this.isAddingVisit) {
        this.map.on('click', this.onMapClick, this);
      }
    }, 100);

    showFlashMessage('notice', 'Click on the map to place a visit');
  }

  exitAddVisitMode(button) {
    this.isAddingVisit = false;

    // Reset button style to inactive state
    setAddVisitButtonInactive(button, this.userThemeValue || 'dark');

    // Reset cursor
    this.map.getContainer().style.cursor = '';

    // Remove map click listener
    this.map.off('click', this.onMapClick, this);

    // Remove any existing marker
    if (this.addVisitMarker) {
      this.map.removeLayer(this.addVisitMarker);
      this.addVisitMarker = null;
    }

    // Close any open popup
    if (this.currentPopup) {
      this.map.closePopup(this.currentPopup);
      this.currentPopup = null;
    } else {
      console.warn('No currentPopup reference found');
      // Fallback: try to close any open popup
      this.map.closePopup();
    }
  }

  onMapClick(e) {
    if (!this.isAddingVisit) return;

    const { lat, lng } = e.latlng;

    // Remove existing marker if any
    if (this.addVisitMarker) {
      this.map.removeLayer(this.addVisitMarker);
    }

    // Create a new marker at the clicked location
    this.addVisitMarker = L.marker([lat, lng], {
      draggable: true,
      icon: L.divIcon({
        className: 'add-visit-marker',
        html: '📍',
        iconSize: [30, 30],
        iconAnchor: [15, 15]
      })
    }).addTo(this.map);

    // Show the visit form popup
    this.showVisitForm(lat, lng);
  }

  showVisitForm(lat, lng) {
    // Close any existing popup first to ensure only one popup is open
    if (this.currentPopup) {
      this.map.closePopup(this.currentPopup);
      this.currentPopup = null;
    }

    // Get current date/time for default values
    const now = new Date();
    const oneHourLater = new Date(now.getTime() + (60 * 60 * 1000));

    // Format dates for datetime-local input
    const formatDateTime = (date) => {
      return date.toISOString().slice(0, 16);
    };

    const startTime = formatDateTime(now);
    const endTime = formatDateTime(oneHourLater);

    // Create form HTML using DaisyUI classes for automatic theme support
    const formHTML = `
      <div class="visit-form" style="min-width: 280px;">
        <h3 class="text-base font-semibold mb-4">Add New Visit</h3>

        <form id="add-visit-form" class="space-y-3">
          <div class="form-control">
            <label for="visit-name" class="label">
              <span class="label-text font-medium">Name:</span>
            </label>
            <input type="text" id="visit-name" name="name" required
                   class="input input-bordered w-full"
                   placeholder="Enter visit name">
          </div>

          <div class="form-control">
            <label for="visit-start" class="label">
              <span class="label-text font-medium">Start Time:</span>
            </label>
            <input type="datetime-local" id="visit-start" name="started_at" required value="${startTime}"
                   class="input input-bordered w-full">
          </div>

          <div class="form-control">
            <label for="visit-end" class="label">
              <span class="label-text font-medium">End Time:</span>
            </label>
            <input type="datetime-local" id="visit-end" name="ended_at" required value="${endTime}"
                   class="input input-bordered w-full">
          </div>

          <input type="hidden" name="latitude" value="${lat}">
          <input type="hidden" name="longitude" value="${lng}">

          <div class="flex gap-2 mt-4">
            <button type="submit" class="btn btn-success flex-1">
              Create Visit
            </button>
            <button type="button" id="cancel-visit" class="btn btn-error flex-1">
              Cancel
            </button>
          </div>
        </form>
      </div>
    `;

    // Create popup at the marker location
    this.currentPopup = L.popup({
      closeOnClick: false,
      autoClose: false,
      maxWidth: 300,
      className: 'visit-form-popup'
    })
      .setLatLng([lat, lng])
      .setContent(formHTML)
      .openOn(this.map);

    // Add event listeners after the popup is added to DOM
    setTimeout(() => {
      const form = document.getElementById('add-visit-form');
      const cancelButton = document.getElementById('cancel-visit');
      const nameInput = document.getElementById('visit-name');

      if (form) {
        form.addEventListener('submit', (e) => this.handleFormSubmit(e));
      }

      if (cancelButton) {
        cancelButton.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();

          this.exitAddVisitMode(this.addVisitButton);
        });
      }

      // Focus the name input
      if (nameInput) {
        nameInput.focus();
      }
    }, 100);
  }

  async handleFormSubmit(event) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);

    // Get form values
    const visitData = {
      visit: {
        name: formData.get('name'),
        started_at: formData.get('started_at'),
        ended_at: formData.get('ended_at'),
        latitude: formData.get('latitude'),
        longitude: formData.get('longitude'),
        status: 'confirmed' // Manually created visits should be confirmed
      }
    };

    // Validate that end time is after start time
    const startTime = new Date(visitData.visit.started_at);
    const endTime = new Date(visitData.visit.ended_at);

    if (endTime <= startTime) {
      showFlashMessage('error', 'End time must be after start time');
      return;
    }

    // Disable form while submitting
    const submitButton = form.querySelector('button[type="submit"]');
    const originalText = submitButton.textContent;
    submitButton.disabled = true;
    submitButton.textContent = 'Creating...';

    try {
      const response = await fetch(`/api/v1/visits`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.apiKeyValue}`
        },
        body: JSON.stringify(visitData)
      });

      const data = await response.json();

      if (response.ok) {
        showFlashMessage('notice', `Visit "${visitData.visit.name}" created successfully!`);

        // Store the created visit data
        const createdVisit = data;

        this.exitAddVisitMode(this.addVisitButton);

        // Add the newly created visit marker immediately to the map
        this.addCreatedVisitToMap(createdVisit, visitData.visit.latitude, visitData.visit.longitude);
      } else {
        const errorMessage = data.error || data.message || 'Failed to create visit';
        showFlashMessage('error', errorMessage);
      }
    } catch (error) {
      console.error('Error creating visit:', error);
      showFlashMessage('error', 'Network error: Failed to create visit');
    } finally {
      // Re-enable form
      submitButton.disabled = false;
      submitButton.textContent = originalText;
    }
  }

  addCreatedVisitToMap(visitData, latitude, longitude) {
    const mapsController = document.querySelector('[data-controller*="maps"]');
    if (!mapsController) {
      console.log('Could not find maps controller element');
      return;
    }

    const stimulusController = this.application.getControllerForElementAndIdentifier(mapsController, 'maps');
    if (!stimulusController || !stimulusController.visitsManager) {
      console.log('Could not find maps controller or visits manager');

      return;
    }

    const visitsManager = stimulusController.visitsManager;

    // Create a circle for the newly created visit (always confirmed)
    const circle = L.circle([latitude, longitude], {
      color: '#4A90E2', // Border color for confirmed visits
      fillColor: '#4A90E2', // Fill color for confirmed visits
      fillOpacity: 0.5,
      radius: 110, // Confirmed visit size
      weight: 2,
      interactive: true,
      bubblingMouseEvents: false,
      pane: 'confirmedVisitsPane'
    });

    // Add the circle to the confirmed visits layer
    visitsManager.confirmedVisitCircles.addLayer(circle);

    // Make sure the layer is visible on the map
    if (!this.map.hasLayer(visitsManager.confirmedVisitCircles)) {
      this.map.addLayer(visitsManager.confirmedVisitCircles);
    }

    // Check if the layer control has the confirmed visits layer enabled
    this.ensureConfirmedVisitsLayerEnabled();
  }

  ensureConfirmedVisitsLayerEnabled() {
    // Find the layer control and check/enable the "Confirmed Visits" checkbox
    const layerControlContainer = document.querySelector('.leaflet-control-layers');
    if (!layerControlContainer) {
      console.log('Layer control container not found');
      return;
    }

    // Expand the layer control if it's collapsed
    const layerControlExpand = layerControlContainer.querySelector('.leaflet-control-layers-toggle');
    if (layerControlExpand) {
      layerControlExpand.click();
    }

    setTimeout(() => {
      const inputs = layerControlContainer.querySelectorAll('input[type="checkbox"]');
      inputs.forEach(input => {
        const label = input.nextElementSibling;
        if (label && label.textContent.trim().includes('Confirmed Visits')) {
          if (!input.checked) {
            input.checked = true;
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      });
    }, 100);
  }

  refreshVisitsLayer() {
    // Don't auto-refresh after creating a visit
    // The visit is already visible on the map from addCreatedVisitToMap()
    // Auto-refresh would clear it because fetchAndDisplayVisits uses URL date params
    // which might not include the newly created visit
    console.log('Skipping auto-refresh - visit already added to map');
  }


  cleanup() {
    if (this.map) {
      this.map.off('click', this.onMapClick, this);

      if (this.addVisitMarker) {
        this.map.removeLayer(this.addVisitMarker);
      }

      if (this.currentPopup) {
        this.map.closePopup(this.currentPopup);
      }
    }
  }
}
