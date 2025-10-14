import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import { showFlashMessage } from "../maps/helpers";
import { applyThemeToButton } from "../maps/theme_utils";

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

    // Create the Add Visit control
    const AddVisitControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'leaflet-control-button add-visit-button');
        button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-check-icon lucide-map-pin-check"><path d="M19.43 12.935c.357-.967.57-1.955.57-2.935a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32.197 32.197 0 0 0 .813-.728"/><circle cx="12" cy="10" r="3"/><path d="m16 18 2 2 4-4"/></svg>';
        button.title = 'Add a visit';

        // Style the button with theme-aware styling
        applyThemeToButton(button, this.userThemeValue || 'dark');
        button.style.width = '48px';
        button.style.height = '48px';
        button.style.borderRadius = '4px';
        button.style.padding = '0';
        button.style.lineHeight = '48px';
        button.style.fontSize = '18px';
        button.style.textAlign = 'center';
        button.style.transition = 'all 0.2s ease';

        // Disable map interactions when clicking the button
        L.DomEvent.disableClickPropagation(button);

        // Toggle add visit mode on button click
        L.DomEvent.on(button, 'click', () => {
          this.toggleAddVisitMode(button);
        });

        this.addVisitButton = button;
        return button;
      }
    });

    // Add the control to the map (top right, below existing buttons)
    this.map.addControl(new AddVisitControl({ position: 'topright' }));
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
    button.style.backgroundColor = '#dc3545';
    button.style.color = 'white';
    button.innerHTML = '✕';

    // Change cursor to crosshair
    this.map.getContainer().style.cursor = 'crosshair';

    // Add map click listener
    this.map.on('click', this.onMapClick, this);

    showFlashMessage('notice', 'Click on the map to place a visit');
  }

  exitAddVisitMode(button) {
    this.isAddingVisit = false;

    // Reset button style with theme-aware styling
    applyThemeToButton(button, this.userThemeValue || 'dark');
    button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-check-icon lucide-map-pin-check"><path d="M19.43 12.935c.357-.967.57-1.955.57-2.935a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32.197 32.197 0 0 0 .813-.728"/><circle cx="12" cy="10" r="3"/><path d="m16 18 2 2 4-4"/></svg>';

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
        cancelButton.addEventListener('click', () => {
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
        longitude: formData.get('longitude')
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
        this.exitAddVisitMode(this.addVisitButton);

        // Refresh visits layer - this will clear and refetch data
        this.refreshVisitsLayer();

        // Ensure confirmed visits layer is enabled (with a small delay for the API call to complete)
        setTimeout(() => {
          this.ensureVisitsLayersEnabled();
        }, 300);
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

  refreshVisitsLayer() {
    console.log('Attempting to refresh visits layer...');

    // Try multiple approaches to refresh the visits layer
    const mapsController = document.querySelector('[data-controller*="maps"]');
    if (mapsController) {
      // Try to get the Stimulus controller instance
      const stimulusController = this.application.getControllerForElementAndIdentifier(mapsController, 'maps');

      if (stimulusController && stimulusController.visitsManager) {
        console.log('Found maps controller with visits manager');

        // Clear existing visits and fetch fresh data
        if (stimulusController.visitsManager.visitCircles) {
          stimulusController.visitsManager.visitCircles.clearLayers();
        }
        if (stimulusController.visitsManager.confirmedVisitCircles) {
          stimulusController.visitsManager.confirmedVisitCircles.clearLayers();
        }

        // Refresh the visits data
        if (typeof stimulusController.visitsManager.fetchAndDisplayVisits === 'function') {
          console.log('Refreshing visits data...');
          stimulusController.visitsManager.fetchAndDisplayVisits();
        }
      } else {
        console.log('Could not find maps controller or visits manager');

        // Fallback: Try to dispatch a custom event
        const refreshEvent = new CustomEvent('visits:refresh', { bubbles: true });
        mapsController.dispatchEvent(refreshEvent);
      }
    } else {
      console.log('Could not find maps controller element');
    }
  }

  ensureVisitsLayersEnabled() {
    console.log('Ensuring visits layers are enabled...');

    const mapsController = document.querySelector('[data-controller*="maps"]');
    if (mapsController) {
      const stimulusController = this.application.getControllerForElementAndIdentifier(mapsController, 'maps');

      if (stimulusController && stimulusController.map && stimulusController.visitsManager) {
        const map = stimulusController.map;
        const visitsManager = stimulusController.visitsManager;

        // Get the confirmed visits layer (newly created visits are always confirmed)
        const confirmedVisitsLayer = visitsManager.getConfirmedVisitCirclesLayer();

        // Ensure confirmed visits layer is added to map since we create confirmed visits
        if (confirmedVisitsLayer && !map.hasLayer(confirmedVisitsLayer)) {
          console.log('Adding confirmed visits layer to map');
          map.addLayer(confirmedVisitsLayer);

          // Update the layer control checkbox to reflect the layer is now active
          this.updateLayerControlCheckbox('Confirmed Visits', true);
        }

        // Refresh visits data to include the new visit
        if (typeof visitsManager.fetchAndDisplayVisits === 'function') {
          console.log('Final refresh of visits to show new visit...');
          visitsManager.fetchAndDisplayVisits();
        }
      }
    }
  }

  updateLayerControlCheckbox(layerName, isEnabled) {
    // Find the layer control input for the specified layer
    const layerControlContainer = document.querySelector('.leaflet-control-layers');
    if (!layerControlContainer) {
      console.log('Layer control container not found');
      return;
    }

    const inputs = layerControlContainer.querySelectorAll('input[type="checkbox"]');
    inputs.forEach(input => {
      const label = input.nextElementSibling;
      if (label && label.textContent.trim() === layerName) {
        console.log(`Updating ${layerName} checkbox to ${isEnabled}`);
        input.checked = isEnabled;

        // Trigger change event to ensure proper state management
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
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
