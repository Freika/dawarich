import L from "leaflet";
import { showFlashMessage } from "./helpers";

/**
 * Manages visits functionality including displaying, fetching, and interacting with visits
 */
export class VisitsManager {
  constructor(map, apiKey) {
    this.map = map;
    this.apiKey = apiKey;
    this.visitCircles = L.layerGroup();
    this.confirmedVisitCircles = L.layerGroup().addTo(map); // Always visible layer for confirmed visits
    this.currentPopup = null;
    this.drawerOpen = false;
  }

  /**
   * Formats a duration in seconds to a human-readable string
   * @param {number} seconds - Duration in seconds
   * @returns {string} Formatted duration string
   */
  formatDuration(seconds) {
    const days = Math.floor(seconds / (24 * 60 * 60));
    const hours = Math.floor((seconds % (24 * 60 * 60)) / (60 * 60));
    const minutes = Math.floor((seconds % (60 * 60)) / 60);

    const parts = [];
    if (days > 0) parts.push(`${days}d`);
    if (hours > 0) parts.push(`${hours}h`);
    if (minutes > 0 && days === 0) parts.push(`${minutes}m`); // Only show minutes if less than a day

    return parts.join(' ') || '< 1m';
  }

  /**
   * Adds a button to toggle the visits drawer
   */
  addDrawerButton() {
    const DrawerControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'leaflet-control-button drawer-button');
        button.innerHTML = '⬅️'; // Left arrow icon
        button.style.width = '48px';
        button.style.height = '48px';
        button.style.border = 'none';
        button.style.cursor = 'pointer';
        button.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';
        button.style.backgroundColor = 'white';
        button.style.borderRadius = '4px';
        button.style.padding = '0';
        button.style.lineHeight = '48px';
        button.style.fontSize = '18px';
        button.style.textAlign = 'center';

        L.DomEvent.disableClickPropagation(button);
        L.DomEvent.on(button, 'click', () => {
          this.toggleDrawer();
        });

        return button;
      }
    });

    this.map.addControl(new DrawerControl({ position: 'topright' }));
  }

  /**
   * Toggles the visibility of the visits drawer
   */
  toggleDrawer() {
    this.drawerOpen = !this.drawerOpen;
    let drawer = document.getElementById('visits-drawer');

    if (!drawer) {
      drawer = this.createDrawer();
    }

    drawer.classList.toggle('open');

    const drawerButton = document.querySelector('.drawer-button');
    if (drawerButton) {
      drawerButton.innerHTML = this.drawerOpen ? '➡️' : '⬅️';
    }

    const controls = document.querySelectorAll('.leaflet-control-layers, .toggle-panel-button, .leaflet-right-panel, .drawer-button');
    controls.forEach(control => {
      control.classList.toggle('controls-shifted');
    });

    // Update the drawer content if it's being opened
    if (this.drawerOpen) {
      this.fetchAndDisplayVisits();
      // Show the suggested visits layer when drawer is open
      if (!this.map.hasLayer(this.visitCircles)) {
        this.map.addLayer(this.visitCircles);
      }
    } else {
      // Hide the suggested visits layer when drawer is closed
      if (this.map.hasLayer(this.visitCircles)) {
        this.map.removeLayer(this.visitCircles);
      }
    }
  }

  /**
   * Creates the drawer element for displaying visits
   * @returns {HTMLElement} The created drawer element
   */
  createDrawer() {
    const drawer = document.createElement('div');
    drawer.id = 'visits-drawer';
    drawer.className = 'fixed top-0 right-0 h-full w-64 bg-base-100 shadow-lg transform translate-x-full transition-transform duration-300 ease-in-out z-39 overflow-y-auto leaflet-drawer';

    // Add styles to make the drawer scrollable
    drawer.style.overflowY = 'auto';
    drawer.style.maxHeight = '100vh';

    drawer.innerHTML = `
      <div class="p-4 drawer">
        <h2 class="text-xl font-bold mb-4 text-accent-content">Recent Visits</h2>
        <div id="visits-list" class="space-y-2">
          <p class="text-gray-500">Loading visits...</p>
        </div>
      </div>
    `;

    // Prevent map zoom when scrolling the drawer
    L.DomEvent.disableScrollPropagation(drawer);
    // Prevent map pan/interaction when interacting with drawer
    L.DomEvent.disableClickPropagation(drawer);

    this.map.getContainer().appendChild(drawer);
    return drawer;
  }

  /**
   * Fetches visits data from the API and displays them
   */
  async fetchAndDisplayVisits() {
    try {
      // Get current timeframe from URL parameters
      const urlParams = new URLSearchParams(window.location.search);
      const startAt = urlParams.get('start_at') || new Date().toISOString();
      const endAt = urlParams.get('end_at') || new Date().toISOString();

      console.log('Fetching visits for:', startAt, endAt);
      const response = await fetch(
        `/api/v1/visits?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
        {
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.apiKey}`,
          }
        }
      );

      if (!response.ok) {
        throw new Error('Network response was not ok');
      }

      const visits = await response.json();
      this.displayVisits(visits);

      // Ensure the suggested visits layer visibility matches the drawer state
      if (this.drawerOpen) {
        if (!this.map.hasLayer(this.visitCircles)) {
          this.map.addLayer(this.visitCircles);
        }
      } else {
        if (this.map.hasLayer(this.visitCircles)) {
          this.map.removeLayer(this.visitCircles);
        }
      }
    } catch (error) {
      console.error('Error fetching visits:', error);
      const container = document.getElementById('visits-list');
      if (container) {
        container.innerHTML = '<p class="text-red-500">Error loading visits</p>';
      }
    }
  }

  /**
   * Displays visits on the map and in the drawer
   * @param {Array} visits - Array of visit objects
   */
  displayVisits(visits) {
    const container = document.getElementById('visits-list');
    if (!container) return;

    if (!visits || visits.length === 0) {
      container.innerHTML = '<p class="text-gray-500">No visits found in selected timeframe</p>';
      return;
    }

    // Clear existing visit circles
    this.visitCircles.clearLayers();
    this.confirmedVisitCircles.clearLayers();

    // Draw circles for all visits
    visits
      .filter(visit => visit.status !== 'declined')
      .forEach(visit => {
        if (visit.place?.latitude && visit.place?.longitude) {
          const isConfirmed = visit.status === 'confirmed';
          const isSuggested = visit.status === 'suggested';

          const circle = L.circle([visit.place.latitude, visit.place.longitude], {
            color: isSuggested ? '#FFA500' : '#4A90E2', // Border color
            fillColor: isSuggested ? '#FFD700' : '#4A90E2', // Fill color
            fillOpacity: isSuggested ? 0.4 : 0.6,
            radius: isConfirmed ? 110 : 80, // Increased size for confirmed visits
            weight: 2,
            interactive: true,
            bubblingMouseEvents: false,
            pane: isConfirmed ? 'confirmedVisitsPane' : 'suggestedVisitsPane', // Use appropriate pane
            dashArray: isSuggested ? '4' : null // Dotted border for suggested
          });

          // Add the circle to the appropriate layer
          if (isConfirmed) {
            this.confirmedVisitCircles.addLayer(circle);
          } else {
            this.visitCircles.addLayer(circle);
          }

          // Attach click event to the circle
          circle.on('click', () => this.fetchPossiblePlaces(visit));
        }
      });

    const html = visits
      // Filter out declined visits
      .filter(visit => visit.status !== 'declined')
      .map(visit => {
        const startDate = new Date(visit.started_at);
        const endDate = new Date(visit.ended_at);
        const isSameDay = startDate.toDateString() === endDate.toDateString();

        let timeDisplay;
        if (isSameDay) {
          timeDisplay = `
            ${startDate.toLocaleDateString(undefined, { month: 'long', day: 'numeric' })},
            ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
            ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })}
          `;
        } else {
          timeDisplay = `
            ${startDate.toLocaleDateString(undefined, { month: 'long', day: 'numeric' })},
            ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
            ${endDate.toLocaleDateString(undefined, { month: 'long', day: 'numeric' })},
            ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })}
          `;
        }

        const durationText = this.formatDuration(visit.duration * 60);

        // Add opacity class for suggested visits
        const bgClass = visit.status === 'suggested' ? 'bg-neutral border-dashed border-2 border-sky-500' : 'bg-base-200';
        const visitStyle = visit.status === 'suggested' ? 'border: 2px dashed #60a5fa;' : '';

        return `
          <div class="w-full p-3 rounded-lg hover:bg-base-300 transition-colors visit-item relative ${bgClass}"
               style="${visitStyle}"
               data-lat="${visit.place?.latitude || ''}"
               data-lng="${visit.place?.longitude || ''}"
               data-id="${visit.id}">
            <div class="absolute top-2 left-2 opacity-0 transition-opacity duration-200 visit-checkbox-container">
              <input type="checkbox" class="checkbox checkbox-sm visit-checkbox" data-id="${visit.id}">
            </div>
            <div class="font-semibold overflow-hidden text-ellipsis whitespace-nowrap pl-6" title="${visit.name}">${this.truncateText(visit.name, 30)}</div>
            <div class="text-sm text-gray-600">
              ${timeDisplay.trim()}
              <div class="text-gray-500">(${durationText})</div>
            </div>
            ${visit.place?.city ? `<div class="text-sm">${visit.place.city}, ${visit.place.country}</div>` : ''}
            ${visit.status !== 'confirmed' ? `
              <div class="flex gap-2 mt-2">
                <button class="btn btn-xs btn-success confirm-visit" data-id="${visit.id}">
                  Confirm
                </button>
                <button class="btn btn-xs btn-error decline-visit" data-id="${visit.id}">
                  Decline
                </button>
              </div>
            ` : ''}
          </div>
        `;
      }).join('');

    container.innerHTML = html;

    // Add the circles layer to the map
    this.visitCircles.addTo(this.map);

    // Add click handlers to visit items and buttons
    this.addVisitItemEventListeners(container);

    // Add merge functionality
    this.setupMergeFunctionality(container);

    // Ensure all checkboxes are hidden by default
    container.querySelectorAll('.visit-checkbox-container').forEach(checkboxContainer => {
      checkboxContainer.style.opacity = '0';
      checkboxContainer.style.pointerEvents = 'none';
    });
  }

  /**
   * Sets up the merge functionality for visits
   * @param {HTMLElement} container - The container with visit items
   */
  setupMergeFunctionality(container) {
    const visitItems = container.querySelectorAll('.visit-item');

    // Add hover event to show checkboxes
    visitItems.forEach(item => {
      // Show checkbox on hover only if no checkboxes are currently checked
      item.addEventListener('mouseenter', () => {
        const allChecked = container.querySelectorAll('.visit-checkbox:checked');
        if (allChecked.length === 0) {
          const checkbox = item.querySelector('.visit-checkbox-container');
          if (checkbox) {
            checkbox.style.opacity = '1';
            checkbox.style.pointerEvents = 'auto';
          }
        }
      });

      // Hide checkbox on mouse leave if not checked and if no other checkboxes are checked
      item.addEventListener('mouseleave', () => {
        const allChecked = container.querySelectorAll('.visit-checkbox:checked');
        if (allChecked.length === 0) {
          const checkbox = item.querySelector('.visit-checkbox-container');
          const checkboxInput = item.querySelector('.visit-checkbox');
          if (checkbox && checkboxInput && !checkboxInput.checked) {
            checkbox.style.opacity = '0';
            checkbox.style.pointerEvents = 'none';
          }
        }
      });
    });

    // Add change event to checkboxes
    const checkboxes = container.querySelectorAll('.visit-checkbox');
    checkboxes.forEach(checkbox => {
      checkbox.addEventListener('change', () => {
        this.updateMergeUI(container);
      });
    });
  }

  /**
   * Updates the merge UI based on selected checkboxes
   * @param {HTMLElement} container - The container with visit items
   */
  updateMergeUI(container) {
    // Remove any existing action buttons
    const existingActionButtons = container.querySelector('.visit-bulk-actions');
    if (existingActionButtons) {
      existingActionButtons.remove();
    }

    // Get all checked checkboxes
    const checkedBoxes = container.querySelectorAll('.visit-checkbox:checked');

    // Hide all checkboxes first
    container.querySelectorAll('.visit-checkbox-container').forEach(checkboxContainer => {
      checkboxContainer.style.opacity = '0';
      checkboxContainer.style.pointerEvents = 'none';
    });

    // If no checkboxes are checked, we're done
    if (checkedBoxes.length === 0) {
      return;
    }

    // Get all visit items and their data
    const visitItems = Array.from(container.querySelectorAll('.visit-item'));

    // For each checked visit, show checkboxes for adjacent visits
    Array.from(checkedBoxes).forEach(checkbox => {
      const visitItem = checkbox.closest('.visit-item');
      const visitId = checkbox.dataset.id;
      const index = visitItems.indexOf(visitItem);

      // Show checkbox for the current visit
      const currentCheckbox = visitItem.querySelector('.visit-checkbox-container');
      if (currentCheckbox) {
        currentCheckbox.style.opacity = '1';
        currentCheckbox.style.pointerEvents = 'auto';
      }

      // Show checkboxes for visits above and below
      // Above visit
      if (index > 0) {
        const aboveVisitItem = visitItems[index - 1];
        const aboveCheckbox = aboveVisitItem.querySelector('.visit-checkbox-container');
        if (aboveCheckbox) {
          aboveCheckbox.style.opacity = '1';
          aboveCheckbox.style.pointerEvents = 'auto';
        }
      }

      // Below visit
      if (index < visitItems.length - 1) {
        const belowVisitItem = visitItems[index + 1];
        const belowCheckbox = belowVisitItem.querySelector('.visit-checkbox-container');
        if (belowCheckbox) {
          belowCheckbox.style.opacity = '1';
          belowCheckbox.style.pointerEvents = 'auto';
        }
      }
    });

    // If 2 or more checkboxes are checked, show action buttons
    if (checkedBoxes.length >= 2) {
      // Find the lowest checked visit item
      let lowestVisitItem = null;
      let lowestPosition = -1;

      checkedBoxes.forEach(checkbox => {
        const visitItem = checkbox.closest('.visit-item');
        const position = visitItems.indexOf(visitItem);

        if (lowestPosition === -1 || position > lowestPosition) {
          lowestPosition = position;
          lowestVisitItem = visitItem;
        }
      });

      // Create action buttons container
      if (lowestVisitItem) {
        // Create a container for the action buttons to ensure proper spacing
        const actionsContainer = document.createElement('div');
        actionsContainer.className = 'w-full p-2 visit-bulk-actions';

        // Create button grid
        const buttonGrid = document.createElement('div');
        buttonGrid.className = 'grid grid-cols-3 gap-2';

        // Merge button
        const mergeButton = document.createElement('button');
        mergeButton.className = 'btn btn-xs btn-primary';
        mergeButton.textContent = 'Merge';
        mergeButton.addEventListener('click', () => {
          this.mergeVisits(Array.from(checkedBoxes).map(cb => cb.dataset.id));
        });

        // Confirm button
        const confirmButton = document.createElement('button');
        confirmButton.className = 'btn btn-xs btn-success';
        confirmButton.textContent = 'Confirm';
        confirmButton.addEventListener('click', () => {
          this.bulkUpdateVisitStatus(Array.from(checkedBoxes).map(cb => cb.dataset.id), 'confirmed');
        });

        // Decline button
        const declineButton = document.createElement('button');
        declineButton.className = 'btn btn-xs btn-error';
        declineButton.textContent = 'Decline';
        declineButton.addEventListener('click', () => {
          this.bulkUpdateVisitStatus(Array.from(checkedBoxes).map(cb => cb.dataset.id), 'declined');
        });

        // Add buttons to grid
        buttonGrid.appendChild(mergeButton);
        buttonGrid.appendChild(confirmButton);
        buttonGrid.appendChild(declineButton);

        // Add selection count text
        const selectionText = document.createElement('div');
        selectionText.className = 'text-sm text-center mt-1 text-gray-500';
        selectionText.textContent = `${checkedBoxes.length} visits selected`;

        // Add elements to container
        actionsContainer.appendChild(buttonGrid);
        actionsContainer.appendChild(selectionText);

        // Insert after the lowest visit item
        lowestVisitItem.insertAdjacentElement('afterend', actionsContainer);
      }
    }

    // Show all checkboxes when at least one is checked
    const checkboxContainers = container.querySelectorAll('.visit-checkbox-container');
    checkboxContainers.forEach(checkboxContainer => {
      checkboxContainer.style.opacity = '1';
      checkboxContainer.style.pointerEvents = 'auto';
    });
  }

  /**
   * Sends a request to merge the selected visits
   * @param {Array} visitIds - Array of visit IDs to merge
   */
  async mergeVisits(visitIds) {
    if (!visitIds || visitIds.length < 2) {
      showFlashMessage('error', 'At least 2 visits must be selected for merging');
      return;
    }

    try {
      const response = await fetch('/api/v1/visits/merge', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          visit_ids: visitIds
        })
      });

      if (!response.ok) {
        throw new Error('Failed to merge visits');
      }

      showFlashMessage('notice', 'Visits merged successfully');

      // Refresh the visits list
      this.fetchAndDisplayVisits();
    } catch (error) {
      console.error('Error merging visits:', error);
      showFlashMessage('error', 'Failed to merge visits');
    }
  }

  /**
   * Sends a request to update status for multiple visits
   * @param {Array} visitIds - Array of visit IDs to update
   * @param {string} status - The new status ('confirmed' or 'declined')
   */
  async bulkUpdateVisitStatus(visitIds, status) {
    if (!visitIds || visitIds.length === 0) {
      showFlashMessage('error', 'No visits selected');
      return;
    }

    try {
      const response = await fetch('/api/v1/visits/bulk_update', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          visit_ids: visitIds,
          status: status
        })
      });

      if (!response.ok) {
        throw new Error(`Failed to ${status} visits`);
      }

      showFlashMessage('notice', `${visitIds.length} visits ${status === 'confirmed' ? 'confirmed' : 'declined'} successfully`);

      // Refresh the visits list
      this.fetchAndDisplayVisits();
    } catch (error) {
      console.error(`Error ${status}ing visits:`, error);
      showFlashMessage('error', `Failed to ${status} visits`);
    }
  }

  /**
   * Adds event listeners to visit items in the drawer
   * @param {HTMLElement} container - The container element with visit items
   */
  addVisitItemEventListeners(container) {
    const visitItems = container.querySelectorAll('.visit-item');
    visitItems.forEach(item => {
      // Location click handler
      item.addEventListener('click', (event) => {
        // Don't trigger if clicking on buttons or checkboxes
        if (event.target.classList.contains('btn') ||
            event.target.classList.contains('checkbox') ||
            event.target.closest('.visit-checkbox-container')) {
          return;
        }

        const lat = parseFloat(item.dataset.lat);
        const lng = parseFloat(item.dataset.lng);

        if (!isNaN(lat) && !isNaN(lng)) {
          this.map.setView([lat, lng], 15, {
            animate: true,
            duration: 1
          });
        }
      });

      // Confirm button handler
      const confirmBtn = item.querySelector('.confirm-visit');
      confirmBtn?.addEventListener('click', async (event) => {
        event.stopPropagation();
        const visitId = event.target.dataset.id;
        try {
          const response = await fetch(`/api/v1/visits/${visitId}`, {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({
              visit: {
                status: 'confirmed'
              }
            })
          });

          if (!response.ok) throw new Error('Failed to confirm visit');

          // Refresh visits list
          this.fetchAndDisplayVisits();
          showFlashMessage('notice', 'Visit confirmed successfully');
        } catch (error) {
          console.error('Error confirming visit:', error);
          showFlashMessage('error', 'Failed to confirm visit');
        }
      });

      // Decline button handler
      const declineBtn = item.querySelector('.decline-visit');
      declineBtn?.addEventListener('click', async (event) => {
        event.stopPropagation();
        const visitId = event.target.dataset.id;
        try {
          const response = await fetch(`/api/v1/visits/${visitId}`, {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({
              visit: {
                status: 'declined'
              }
            })
          });

          if (!response.ok) throw new Error('Failed to decline visit');

          // Refresh visits list
          this.fetchAndDisplayVisits();
          showFlashMessage('notice', 'Visit declined successfully');
        } catch (error) {
          console.error('Error declining visit:', error);
          showFlashMessage('error', 'Failed to decline visit');
        }
      });
    });
  }

  /**
   * Fetches possible places for a visit and displays them in a popup
   * @param {Object} visit - The visit object
   */
  async fetchPossiblePlaces(visit) {
    try {
      // Close any existing popup before opening a new one
      if (this.currentPopup) {
        this.map.closePopup(this.currentPopup);
        this.currentPopup = null;
      }

      const response = await fetch(`/api/v1/visits/${visit.id}/possible_places`, {
        headers: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        }
      });

      if (!response.ok) throw new Error('Failed to fetch possible places');

      const possiblePlaces = await response.json();

      // Format date and time
      const startDate = new Date(visit.started_at);
      const endDate = new Date(visit.ended_at);
      const isSameDay = startDate.toDateString() === endDate.toDateString();

      let dateTimeDisplay;
      if (isSameDay) {
        dateTimeDisplay = `
          ${startDate.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })},
          ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
          ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })}
        `;
      } else {
        dateTimeDisplay = `
          ${startDate.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })},
          ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
          ${endDate.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })},
          ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })}
        `;
      }

      // Format duration
      const durationText = this.formatDuration(visit.duration * 60);

      // Status with color coding
      const statusColorClass = visit.status === 'confirmed' ? 'text-success' : 'text-warning';

      // Create popup content with form and dropdown
      const defaultName = visit.name;
      const popupContent = `
        <div class="p-3">
          <div class="mb-3">
            <div class="text-sm mb-1">
              ${dateTimeDisplay.trim()}
            </div>
            <div>
              <span class="text-sm text-gray-500">
                Duration: ${durationText},
              </span>
              <span class="text-sm mb-1 ${statusColorClass} font-semibold">
                status: ${visit.status.charAt(0).toUpperCase() + visit.status.slice(1)}
              </span>
            </div>
          </div>
          <form class="visit-name-form" data-visit-id="${visit.id}">
            <div class="form-control">
              <input type="text"
                     class="input input-bordered input-sm w-full text-neutral-content"
                     value="${defaultName}"
                     placeholder="Enter visit name">
            </div>
            <div class="form-control mt-2">
              <select class="select text-neutral-content select-bordered select-sm w-full h-fit" name="place">
                ${possiblePlaces.map(place => `
                  <option value="${place.id}" ${place.id === visit.place.id ? 'selected' : ''}>
                    ${place.name}
                  </option>
                `).join('')}
              </select>
            </div>
            <div class="flex gap-2 mt-2">
              <button type="submit" class="btn btn-xs btn-primary">Save</button>
              ${visit.status !== 'confirmed' ? `
                <button type="button" class="btn btn-xs btn-success confirm-visit" data-id="${visit.id}">Confirm</button>
                <button type="button" class="btn btn-xs btn-error decline-visit" data-id="${visit.id}">Decline</button>
              ` : ''}
            </div>
          </form>
        </div>
      `;

      // Create and store the popup
      const popup = L.popup({
        closeButton: true,
        closeOnClick: true,
        autoClose: true,
        maxWidth: 450, // Set maximum width
        minWidth: 300  // Set minimum width
      })
        .setLatLng([visit.place.latitude, visit.place.longitude])
        .setContent(popupContent);

      // Store the current popup
      this.currentPopup = popup;

      // Open the popup
      popup.openOn(this.map);

      // Add form submit handler
      this.addPopupFormEventListeners(visit);
    } catch (error) {
      console.error('Error fetching possible places:', error);
      showFlashMessage('error', 'Failed to load possible places');
    }
  }

  /**
   * Adds event listeners to the popup form
   * @param {Object} visit - The visit object
   */
  addPopupFormEventListeners(visit) {
    const form = document.querySelector(`.visit-name-form[data-visit-id="${visit.id}"]`);
    if (form) {
      form.addEventListener('submit', async (event) => {
        event.preventDefault(); // Prevent form submission
        event.stopPropagation(); // Stop event bubbling
        const newName = event.target.querySelector('input').value;
        const selectedPlaceId = event.target.querySelector('select[name="place"]').value;

        // Get the selected place name from the dropdown
        const selectedOption = event.target.querySelector(`select[name="place"] option[value="${selectedPlaceId}"]`);
        const selectedPlaceName = selectedOption ? selectedOption.textContent.trim() : '';

        console.log('Selected new place:', selectedPlaceName);

        try {
          const response = await fetch(`/api/v1/visits/${visit.id}`, {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({
              visit: {
                name: newName,
                place_id: selectedPlaceId
              }
            })
          });

          if (!response.ok) throw new Error('Failed to update visit');

          // Get the updated visit data from the response
          const updatedVisit = await response.json();

          // Update the local visit object with the latest data
          // This ensures that if the popup is opened again, it will show the updated values
          visit.name = updatedVisit.name || newName;
          visit.place = updatedVisit.place;

          // Use the selected place name for the update
          const updatedName = selectedPlaceName || newName;
          console.log('Updating visit name in drawer to:', updatedName);

          // Update the visit name in the drawer panel
          const drawerVisitItem = document.querySelector(`.drawer .visit-item[data-id="${visit.id}"]`);
          if (drawerVisitItem) {
            const nameElement = drawerVisitItem.querySelector('.font-semibold');
            if (nameElement) {
              console.log('Previous name in drawer:', nameElement.textContent);
              nameElement.textContent = updatedName;

              // Add a highlight effect to make the change visible
              nameElement.style.backgroundColor = 'rgba(255, 255, 0, 0.3)';
              setTimeout(() => {
                nameElement.style.backgroundColor = '';
              }, 2000);

              console.log('Updated name in drawer to:', nameElement.textContent);
            }
          }

          // Close the popup
          this.map.closePopup(this.currentPopup);
          this.currentPopup = null;
          showFlashMessage('notice', 'Visit updated successfully');
        } catch (error) {
          console.error('Error updating visit:', error);
          showFlashMessage('error', 'Failed to update visit');
        }
      });

      // Add event listeners for confirm and decline buttons
      const confirmBtn = form.querySelector('.confirm-visit');
      const declineBtn = form.querySelector('.decline-visit');

      confirmBtn?.addEventListener('click', (event) => this.handleStatusChange(event, visit.id, 'confirmed'));
      declineBtn?.addEventListener('click', (event) => this.handleStatusChange(event, visit.id, 'declined'));
    }
  }

  /**
   * Handles status change for a visit (confirm/decline)
   * @param {Event} event - The click event
   * @param {string} visitId - The visit ID
   * @param {string} status - The new status ('confirmed' or 'declined')
   */
  async handleStatusChange(event, visitId, status) {
    event.preventDefault();
    event.stopPropagation();
    try {
      const response = await fetch(`/api/v1/visits/${visitId}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          visit: {
            status: status
          }
        })
      });

      if (!response.ok) throw new Error(`Failed to ${status} visit`);

      if (this.currentPopup) {
        this.map.closePopup(this.currentPopup);
        this.currentPopup = null;
      }

      this.fetchAndDisplayVisits();
      showFlashMessage('notice', `Visit ${status}d successfully`);
    } catch (error) {
      console.error(`Error ${status}ing visit:`, error);
      showFlashMessage('error', `Failed to ${status} visit`);
    }
  }

  /**
   * Truncates text to a specified length and adds ellipsis if needed
   * @param {string} text - The text to truncate
   * @param {number} maxLength - The maximum length
   * @returns {string} Truncated text
   */
  truncateText(text, maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  }

  /**
   * Gets the visits layer group for adding to the map controls
   * @returns {L.LayerGroup} The visits layer group
   */
  getVisitCirclesLayer() {
    return this.visitCircles;
  }

  /**
   * Gets the confirmed visits layer group that's always visible
   * @returns {L.LayerGroup} The confirmed visits layer group
   */
  getConfirmedVisitCirclesLayer() {
    return this.confirmedVisitCircles;
  }
}
