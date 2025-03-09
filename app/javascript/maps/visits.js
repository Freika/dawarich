import L from "leaflet";
import { showFlashMessage } from "./helpers";

/**
 * Manages visits functionality including displaying, fetching, and interacting with visits
 */
export class VisitsManager {
  constructor(map, apiKey) {
    this.map = map;
    this.apiKey = apiKey;

    // Create custom panes for different visit types
    if (!map.getPane('confirmedVisitsPane')) {
      map.createPane('confirmedVisitsPane');
      map.getPane('confirmedVisitsPane').style.zIndex = 450; // Above default overlay pane (400)
    }

    if (!map.getPane('suggestedVisitsPane')) {
      map.createPane('suggestedVisitsPane');
      map.getPane('suggestedVisitsPane').style.zIndex = 430; // Below confirmed visits but above base layers
    }

    this.visitCircles = L.layerGroup();
    this.confirmedVisitCircles = L.layerGroup().addTo(map); // Always visible layer for confirmed visits
    this.currentPopup = null;
    this.drawerOpen = false;
    this.selectionMode = false;
    this.selectionRect = null;
    this.isSelectionActive = false;
    this.selectedPoints = [];
    this.highlightedVisitId = null;
    this.highlightedCircles = []; // Track multiple circles instead of just one

    // Add CSS for visit highlighting
    const style = document.createElement('style');
    style.textContent = `
      .visit-highlighted {
        transition: all 0.3s ease-in-out;
      }
    `;
    document.head.appendChild(style);
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

    // Add the selection tool button
    this.addSelectionButton();
  }

  /**
   * Adds a button to enable/disable the area selection tool
   */
  addSelectionButton() {
    const SelectionControl = L.Control.extend({
      onAdd: (map) => {
        const button = L.DomUtil.create('button', 'leaflet-bar leaflet-control leaflet-control-custom');
        button.innerHTML = '📌';
        button.title = 'Select Area';
        button.id = 'selection-tool-button';
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
        button.onclick = () => this.toggleSelectionMode();
        return button;
      }
    });

    new SelectionControl({ position: 'topright' }).addTo(this.map);
  }

  /**
   * Toggles the area selection mode
   */
  toggleSelectionMode() {
    // Clear any existing highlight
    this.clearVisitHighlight();

    this.isSelectionActive = !this.isSelectionActive;
    if (this.selectionMode) {
      // Disable selection mode
      this.selectionMode = false;
      this.map.dragging.enable();
      document.getElementById('selection-tool-button').classList.remove('active');
      this.map.off('mousedown', this.onMouseDown, this);
    } else {
      // Enable selection mode
      this.selectionMode = true;
      document.getElementById('selection-tool-button').classList.add('active');
      this.map.dragging.disable();
      this.map.on('mousedown', this.onMouseDown, this);

      showFlashMessage('info', 'Selection mode enabled. Click and drag to select an area.');
    }
  }

  /**
   * Handles the mousedown event to start the selection
   */
  onMouseDown(e) {
    // Clear any existing selection
    this.clearSelection();

    // Store start point and create rectangle
    this.startPoint = e.latlng;

    // Add mousemove and mouseup listeners
    this.map.on('mousemove', this.onMouseMove, this);
    this.map.on('mouseup', this.onMouseUp, this);
  }

  /**
   * Handles the mousemove event to update the selection rectangle
   */
  onMouseMove(e) {
    if (!this.startPoint) return;

    // If we already have a rectangle, update its bounds
    if (this.selectionRect) {
      const bounds = L.latLngBounds(this.startPoint, e.latlng);
      this.selectionRect.setBounds(bounds);
    } else {
      // Create a new rectangle
      this.selectionRect = L.rectangle(
        L.latLngBounds(this.startPoint, e.latlng),
        { color: '#3388ff', weight: 2, fillOpacity: 0.1 }
      ).addTo(this.map);
    }
  }

  /**
   * Handles the mouseup event to complete the selection
   */
  onMouseUp(e) {
    // Remove the mouse event listeners
    this.map.off('mousemove', this.onMouseMove, this);
    this.map.off('mouseup', this.onMouseUp, this);

    if (!this.selectionRect) return;

    // Finalize the selection
    this.isSelectionActive = true;

    // Re-enable map dragging
    this.map.dragging.enable();

    // Disable selection mode
    this.selectionMode = false;
    document.getElementById('selection-tool-button').classList.remove('active');
    this.map.off('mousedown', this.onMouseDown, this);

    // Fetch visits within the selection
    this.fetchVisitsInSelection();
  }

  /**
   * Clears the selection rectangle and resets selection state
   */
  clearSelection() {
    if (this.selectionRect) {
      this.map.removeLayer(this.selectionRect);
      this.selectionRect = null;
    }
    this.isSelectionActive = false;
    this.startPoint = null;
    this.selectedPoints = [];

    // Clear all visit circles immediately
    this.visitCircles.clearLayers();
    this.confirmedVisitCircles.clearLayers();

    // If the drawer is open, refresh with time-based visits
    if (this.drawerOpen) {
      this.fetchAndDisplayVisits();
    } else {
      // If drawer is closed, we should hide all visits
      if (this.map.hasLayer(this.visitCircles)) {
        this.map.removeLayer(this.visitCircles);
      }
    }

    // Reset drawer title
    const drawerTitle = document.querySelector('#visits-drawer .drawer h2');
    if (drawerTitle) {
      drawerTitle.textContent = 'Recent Visits';
    }
  }

  /**
   * Fetches visits within the selected area
   */
  async fetchVisitsInSelection() {
    if (!this.selectionRect) return;

    const bounds = this.selectionRect.getBounds();
    const sw = bounds.getSouthWest();
    const ne = bounds.getNorthEast();

    try {
      const response = await fetch(
        `/api/v1/visits?selection=true&sw_lat=${sw.lat}&sw_lng=${sw.lng}&ne_lat=${ne.lat}&ne_lng=${ne.lng}`,
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

      // Filter points in the selected area from DOM data
      this.filterPointsInSelection(bounds);

      // Set selection as active to ensure date summary is displayed
      this.isSelectionActive = true;

      this.displayVisits(visits);

      // Make sure the drawer is open
      if (!this.drawerOpen) {
        this.toggleDrawer();
      }

      // Add cancel selection button to the drawer
      this.addSelectionCancelButton();

    } catch (error) {
      console.error('Error fetching visits in selection:', error);
      showFlashMessage('error', 'Failed to load visits in selected area');
    }
  }

  /**
   * Filters points from DOM data that are within the selection bounds
   * @param {L.LatLngBounds} bounds - The bounds of the selection rectangle
   */
  filterPointsInSelection(bounds) {
    if (!bounds) {
      this.selectedPoints = [];
      return;
    }

    // Get points from the DOM
    const allPoints = this.getPointsData();
    if (!allPoints || !allPoints.length) {
      this.selectedPoints = [];
      return;
    }

    // Filter points that are within the bounds
    this.selectedPoints = allPoints.filter(point => {
      // Point format is expected to be [lat, lng, ...other data]
      const lat = parseFloat(point[0]);
      const lng = parseFloat(point[1]);

      if (isNaN(lat) || isNaN(lng)) return false;

      return bounds.contains([lat, lng]);
    });
  }

  /**
   * Gets points data from the DOM
   * @returns {Array} Array of points with coordinates and timestamps
   */
  getPointsData() {
    const mapElement = document.getElementById('map');
    if (!mapElement) return [];

    // Get coordinates data from the data attribute
    const coordinatesAttr = mapElement.getAttribute('data-coordinates');
    if (!coordinatesAttr) return [];

    try {
      return JSON.parse(coordinatesAttr);
    } catch (e) {
      console.error('Error parsing coordinates data:', e);
      return [];
    }
  }

  /**
   * Groups visits by date
   * @param {Array} visits - Array of visit objects
   * @returns {Object} Object with dates as keys and counts as values
   */
  groupVisitsByDate(visits) {
    const dateGroups = {};

    visits.forEach(visit => {
      const startDate = new Date(visit.started_at);
      const dateStr = startDate.toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      });

      if (!dateGroups[dateStr]) {
        dateGroups[dateStr] = {
          count: 0,
          points: 0,
          date: startDate
        };
      }

      dateGroups[dateStr].count++;
    });

    // If we have selected points, count them by date
    if (this.selectedPoints && this.selectedPoints.length > 0) {
      this.selectedPoints.forEach(point => {
        // Point timestamp is at index 4
        const timestamp = point[4];
        if (!timestamp) return;

        // Convert timestamp to date string
        const pointDate = new Date(parseInt(timestamp) * 1000);
        const dateStr = pointDate.toLocaleDateString(undefined, {
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        });

        if (!dateGroups[dateStr]) {
          dateGroups[dateStr] = {
            count: 0,
            points: 0,
            date: pointDate
          };
        }

        dateGroups[dateStr].points++;
      });
    }

    return dateGroups;
  }

  /**
   * Creates HTML for date summary panel
   * @param {Object} dateGroups - Object with dates as keys and count/points values
   * @returns {string} HTML string for date summary panel
   */
  createDateSummaryHtml(dateGroups) {
    // If there are no date groups, return empty string
    if (Object.keys(dateGroups).length === 0) {
      return '';
    }

    // Sort dates chronologically
    const sortedDates = Object.keys(dateGroups).sort((a, b) => {
      return dateGroups[a].date - dateGroups[b].date;
    });

    // Create HTML for each date group
    const dateItems = sortedDates.map(dateStr => {
      const pointsCount = dateGroups[dateStr].points || 0;
      const visitsCount = dateGroups[dateStr].count || 0;

      return `
        <div class="flex justify-between items-center py-1 border-b border-base-300 last:border-0 my-2">
          <div class="font-medium">${dateStr}</div>
          <div class="flex gap-2">
            ${pointsCount > 0 ? `<div class="badge badge-secondary">${pointsCount} points</div>` : ''}
            ${visitsCount > 0 ? `<div class="badge badge-primary">${visitsCount} visits</div>` : ''}
          </div>
        </div>
      `;
    }).join('');

    // Create the whole panel
    return `
      <div class="bg-base-100 rounded-lg p-3 mb-4 shadow-sm">
        <h3 class="text-lg font-bold mb-2">Data in Selected Area</h3>
        <div class="divide-y divide-base-300">
          ${dateItems}
        </div>
      </div>
    `;
  }

  /**
   * Adds a cancel button to the drawer to clear the selection
   */
  addSelectionCancelButton() {
    const container = document.getElementById('visits-list');
    if (!container) return;

    // Add cancel button at the top of the drawer if it doesn't exist
    if (!document.getElementById('cancel-selection-button')) {
      const cancelButton = document.createElement('button');
      cancelButton.id = 'cancel-selection-button';
      cancelButton.className = 'btn btn-sm btn-warning mb-4 w-full';
      cancelButton.textContent = 'Cancel Area Selection';
      cancelButton.onclick = () => this.clearSelection();

      // Insert at the beginning of the container
      container.insertBefore(cancelButton, container.firstChild);
    }
  }

  /**
   * Toggles the visibility of the visits drawer
   */
  toggleDrawer() {
    // Clear any existing highlight when drawer is toggled
    this.clearVisitHighlight();

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

    const controls = document.querySelectorAll('.leaflet-control-layers, .toggle-panel-button, .leaflet-right-panel, .drawer-button, #selection-tool-button');
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
      // Clear any existing highlight before fetching new visits
      this.clearVisitHighlight();

      // If there's an active selection, don't perform time-based fetch
      if (this.isSelectionActive && this.selectionRect) {
        this.fetchVisitsInSelection();
        return;
      }

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

    // Update the drawer title if selection is active
    if (this.isSelectionActive && this.selectionRect) {
      const visitsCount = visits ? visits.filter(visit => visit.status !== 'declined').length : 0;
      const drawerTitle = document.querySelector('#visits-drawer .drawer h2');
      if (drawerTitle) {
        drawerTitle.textContent = `${visitsCount} visits found`;
      }
    } else {
      // Reset title to default when not in selection mode
      const drawerTitle = document.querySelector('#visits-drawer .drawer h2');
      if (drawerTitle) {
        drawerTitle.textContent = 'Recent Visits';
      }
    }

    // Group visits by date and count
    const dateGroups = this.groupVisitsByDate(visits || []);

    // If we have points data and are in selection mode, calculate points per date
    let dateGroupsHtml = '';
    if (this.isSelectionActive && this.selectionRect) {
      // Create a date summary panel
      dateGroupsHtml = this.createDateSummaryHtml(dateGroups);
    }

    if (!visits || visits.length === 0) {
      let noVisitsHtml = '<p class="text-gray-500">No visits found in selected timeframe</p>';
      container.innerHTML = dateGroupsHtml + noVisitsHtml;
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
            fillOpacity: isSuggested ? 0.3 : 0.5,
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

    const visitsHtml = visits
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

    // Combine date summary and visits HTML
    container.innerHTML = dateGroupsHtml + visitsHtml;

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

    // Remove existing highlight if any
    this.clearVisitHighlight();

    visitItems.forEach(item => {
      // Location click handler
      item.addEventListener('click', (event) => {
        // Don't trigger if clicking on buttons or checkboxes
        if (event.target.classList.contains('btn') ||
            event.target.classList.contains('checkbox') ||
            event.target.closest('.visit-checkbox-container')) {
          return;
        }

        const visitId = item.dataset.id;
        const lat = parseFloat(item.dataset.lat);
        const lng = parseFloat(item.dataset.lng);

        // Highlight the clicked visit
        this.highlightVisit(visitId, item, [lat, lng]);

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
   * Highlights a visit both in the panel and on the map
   * @param {string} visitId - The ID of the visit to highlight
   * @param {HTMLElement} item - The visit item element in the drawer
   * @param {Array} coords - The coordinates [lat, lng] of the visit
   */
  highlightVisit(visitId, item, coords) {
    // Clear existing highlight
    this.clearVisitHighlight();

    // Store the current highlighted visit ID
    this.highlightedVisitId = visitId;

    // Highlight in the drawer panel
    if (item) {
      item.classList.add('visit-highlighted');
      item.style.border = '2px solid #60a5fa';
      item.style.boxShadow = '0 0 0 2px #60a5fa';
    }

    // Find and highlight the circle on the map
    if (coords && !isNaN(coords[0]) && !isNaN(coords[1])) {
      console.log(`Highlighting visit ID: ${visitId} at coordinates [${coords[0]}, ${coords[1]}]`);

      // Create a Leaflet LatLng object from the coords
      const targetLatLng = L.latLng(coords[0], coords[1]);

      // Helper function to find and highlight circles that are very close to the coords
      const findAndHighlightCircles = (layerGroup) => {
        layerGroup.eachLayer(layer => {
          if (layer instanceof L.Circle) {
            // Calculate the distance between circle center and target coordinates
            const distance = targetLatLng.distanceTo(layer.getLatLng());

            // Use a small distance threshold (2 meters)
            if (distance < 2) {
              console.log(`Found matching circle at distance: ${distance.toFixed(2)}m`);

              // Store original style for restoration
              const originalStyle = {
                color: layer.options.color,
                weight: layer.options.weight,
                fillOpacity: layer.options.fillOpacity
              };

              layer._originalStyle = originalStyle;

              // Apply highlighting
              layer.setStyle({
                color: '#f59e0b', // Amber color for highlighting
                weight: 4,
                fillOpacity: 0.7
              });

              // Add to the tracked highlights
              this.highlightedCircles.push(layer);
            }
          }
        });
      };

      // Check in both layer groups
      findAndHighlightCircles(this.visitCircles);
      findAndHighlightCircles(this.confirmedVisitCircles);

      console.log(`Found ${this.highlightedCircles.length} circles to highlight`);
    }
  }

  /**
   * Clears any existing visit highlight
   */
  clearVisitHighlight() {
    // Clear panel highlight
    const highlightedItems = document.querySelectorAll('.visit-highlighted');
    highlightedItems.forEach(el => {
      el.classList.remove('visit-highlighted');
      el.style.border = '';
      el.style.boxShadow = '';
    });

    // Restore original circle styles for all highlighted circles
    console.log(`Clearing ${this.highlightedCircles.length} highlighted circles`);
    this.highlightedCircles.forEach(circle => {
      if (circle && circle._originalStyle) {
        circle.setStyle(circle._originalStyle);
      } else if (circle) {
        console.warn('Circle missing original style during cleanup');
      }
    });

    // Clear the array of highlighted circles
    this.highlightedCircles = [];
    this.highlightedVisitId = null;
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

      // Find and highlight the corresponding visit item in the drawer
      if (visit.id) {
        const visitItem = document.querySelector(`.visit-item[data-id="${visit.id}"]`);
        if (visitItem && visit.place?.latitude && visit.place?.longitude) {
          this.highlightVisit(visit.id, visitItem, [visit.place.latitude, visit.place.longitude]);
        }
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
              <span>${visit.place.latitude}, ${visit.place.longitude}</span>
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
        closeOnEscapeKey: true,
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
