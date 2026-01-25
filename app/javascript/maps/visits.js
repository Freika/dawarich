import L from "leaflet";
import { showFlashMessage } from "./helpers";
import { createPolylinesLayer } from "./polylines";

/**
 * Manages visits functionality including displaying, fetching, and interacting with visits
 */
export class VisitsManager {
  constructor(map, apiKey, userTheme = 'dark', mapsController = null) {
    this.map = map;
    this.apiKey = apiKey;
    this.userTheme = userTheme;
    this.mapsController = mapsController;
    this.timezone = mapsController?.timezone || mapsController?.userSettings?.timezone || 'UTC';

    // Create custom panes for different visit types
    // Leaflet default panes: tilePane=200, overlayPane=400, shadowPane=500, markerPane=600, tooltipPane=650, popupPane=700
    if (!map.getPane('suggestedVisitsPane')) {
      map.createPane('suggestedVisitsPane');
      map.getPane('suggestedVisitsPane').style.zIndex = 610; // Above markerPane (600), below tooltipPane (650)
      map.getPane('suggestedVisitsPane').style.pointerEvents = 'auto'; // Ensure interactions work
    }

    if (!map.getPane('confirmedVisitsPane')) {
      map.createPane('confirmedVisitsPane');
      map.getPane('confirmedVisitsPane').style.zIndex = 620; // Above suggested visits
      map.getPane('confirmedVisitsPane').style.pointerEvents = 'auto'; // Ensure interactions work
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
   * Note: Drawer and selection buttons are now added centrally via addTopRightButtons()
   * in maps_controller.js to ensure correct button ordering.
   *
   * The methods below are kept for backwards compatibility but are no longer called
   * during initialization. Button callbacks are wired directly in maps_controller.js:
   * - onSelectArea -> this.toggleSelectionMode()
   * - onToggleDrawer -> this.toggleDrawer()
   */

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

    // Always refresh visits data regardless of drawer state
    // Layer visibility is now controlled by the layer control, not the drawer
    this.fetchAndDisplayVisits();

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

      // Make sure the drawer is open FIRST, before displaying visits
      if (!this.drawerOpen) {
        this.toggleDrawer();
      }

      // Now display visits in the drawer
      this.displayVisits(visits);

      // Add cancel selection button to the drawer AFTER displayVisits
      // This needs to be after because displayVisits sets innerHTML which would wipe out the buttons
      // Use setTimeout to ensure DOM has fully updated
      setTimeout(() => {
        this.addSelectionCancelButton();
      }, 0);

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
        month: 'short',
        day: 'numeric',
        timeZone: this.timezone
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
          month: 'short',
          day: 'numeric',
          timeZone: this.timezone
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
        <div class="flex justify-between items-center py-1 border-b border-base-300 last:border-0 my-2 hover:bg-accent hover:text-accent-content transition-colors border-radius-md">
          <div class="font-medium">${dateStr}</div>
          <div class="flex gap-2">
            ${pointsCount > 0 ? `<div class="badge badge-secondary">${pointsCount} pts</div>` : ''}
            ${visitsCount > 0 ? `<div class="badge badge-primary">${visitsCount} visits</div>` : ''}
          </div>
        </div>
      `;
    }).join('');

    // Create the whole panel with collapsible content
    return `
      <details id="data-section-collapse" class="collapse collapse-arrow bg-base-100 rounded-lg mb-4 shadow-sm">
        <summary class="collapse-title text-lg font-bold">
          Data in Selected Area
        </summary>
        <div class="collapse-content">
          <div class="divide-y divide-base-300">
            ${dateItems}
          </div>
        </div>
      </details>
    `;
  }

  /**
   * Adds a cancel button to the drawer to clear the selection
   */
  addSelectionCancelButton() {
    const container = document.getElementById('visits-list');
    if (!container) {
      console.error('addSelectionCancelButton: visits-list container not found');
      return;
    }

    // Remove any existing button container first to avoid duplicates
    const existingButtonContainer = document.getElementById('selection-button-container');
    if (existingButtonContainer) {
      existingButtonContainer.remove();
    }

    // Create a button container
    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'flex flex-col gap-2 mb-4';
    buttonContainer.id = 'selection-button-container';

    // Cancel button
    const cancelButton = document.createElement('button');
    cancelButton.id = 'cancel-selection-button';
    cancelButton.className = 'btn btn-sm btn-warning w-full';
    cancelButton.textContent = 'Cancel Selection';
    cancelButton.onclick = () => this.clearSelection();

    // Delete all selected points button
    const deleteButton = document.createElement('button');
    deleteButton.id = 'delete-selection-button';
    deleteButton.className = 'btn btn-sm btn-error w-full';
    deleteButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="inline mr-1"><path d="M3 6h18"></path><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"></path><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"></path></svg>Delete Points';
    deleteButton.onclick = () => this.deleteSelectedPoints();

    // Add count badge if we have selected points
    if (this.selectedPoints && this.selectedPoints.length > 0) {
      const badge = document.createElement('span');
      badge.className = 'badge badge-sm ml-1';
      badge.textContent = this.selectedPoints.length;
      deleteButton.appendChild(badge);
    }

    buttonContainer.appendChild(cancelButton);
    buttonContainer.appendChild(deleteButton);

    // Insert at the beginning of the container
    container.insertBefore(buttonContainer, container.firstChild);
  }

  /**
   * Deletes all points in the current selection
   */
  async deleteSelectedPoints() {
    if (!this.selectedPoints || this.selectedPoints.length === 0) {
      showFlashMessage('warning', 'No points selected');
      return;
    }

    const pointCount = this.selectedPoints.length;
    const confirmed = confirm(
      `⚠️ WARNING: This will permanently delete ${pointCount} point${pointCount > 1 ? 's' : ''} from your location history.\n\n` +
      `This action cannot be undone!\n\n` +
      `Are you sure you want to continue?`
    );

    if (!confirmed) return;

    try {
      // Get point IDs from the selected points
      // Debug: log the structure of selected points
      console.log('Selected points sample:', this.selectedPoints[0]);

      // Points format: [lat, lng, ?, ?, timestamp, ?, id, country, ?]
      // ID is at index 6 based on the marker array structure
      const pointIds = this.selectedPoints
        .map(point => point[6]) // ID is at index 6
        .filter(id => id != null && id !== '');

      console.log('Point IDs to delete:', pointIds);

      if (pointIds.length === 0) {
        showFlashMessage('error', 'No valid point IDs found');
        return;
      }

      // Call the bulk delete API
      const response = await fetch('/api/v1/points/bulk_destroy', {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
        },
        body: JSON.stringify({ point_ids: pointIds })
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('Response error:', response.status, errorText);
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      console.log('Delete result:', result);

      // Check if any points were actually deleted
      if (result.count === 0) {
        showFlashMessage('warning', 'No points were deleted. They may have already been removed.');
        this.clearSelection();
        return;
      }

      // Show success message
      showFlashMessage('notice', `Successfully deleted ${result.count} point${result.count > 1 ? 's' : ''}`);

      // Remove deleted points from the map
      pointIds.forEach(id => {
        this.mapsController.removeMarker(id);
      });

      // Update the polylines layer
      this.updatePolylinesAfterDeletion();

      // Update heatmap with remaining markers
      if (this.mapsController.heatmapLayer) {
        this.mapsController.heatmapLayer.setLatLngs(
          this.mapsController.markers.map(marker => [marker[0], marker[1], 0.2])
        );
      }

      // Update fog if enabled
      if (this.mapsController.fogOverlay && this.mapsController.map.hasLayer(this.mapsController.fogOverlay)) {
        this.mapsController.updateFog(
          this.mapsController.markers,
          this.mapsController.clearFogRadius,
          this.mapsController.fogLineThreshold
        );
      }

      // Clear selection
      this.clearSelection();

    } catch (error) {
      console.error('Error deleting points:', error);
      showFlashMessage('error', 'Failed to delete points. Please try again.');
    }
  }

  /**
   * Updates polylines layer after deletion (similar to single point deletion)
   */
  updatePolylinesAfterDeletion() {
    let wasPolyLayerVisible = false;

    // Check if polylines layer was visible
    if (this.mapsController.polylinesLayer) {
      if (this.mapsController.map.hasLayer(this.mapsController.polylinesLayer)) {
        wasPolyLayerVisible = true;
      }
      this.mapsController.map.removeLayer(this.mapsController.polylinesLayer);
    }

    // Create new polylines layer with updated markers
    this.mapsController.polylinesLayer = createPolylinesLayer(
      this.mapsController.markers,
      this.mapsController.map,
      this.mapsController.timezone,
      this.mapsController.routeOpacity,
      this.mapsController.userSettings,
      this.mapsController.distanceUnit
    );

    // Re-add to map if it was visible, otherwise ensure it's removed
    if (wasPolyLayerVisible) {
      this.mapsController.polylinesLayer.addTo(this.mapsController.map);
    } else {
      this.mapsController.map.removeLayer(this.mapsController.polylinesLayer);
    }

    // Update layer control
    if (this.mapsController.layerControl) {
      this.mapsController.map.removeControl(this.mapsController.layerControl);
      const controlsLayer = {
        Points: this.mapsController.markersLayer || L.layerGroup(),
        Routes: this.mapsController.polylinesLayer || L.layerGroup(),
        Tracks: this.mapsController.tracksLayer || L.layerGroup(),
        Heatmap: this.mapsController.heatmapLayer || L.layerGroup(),
        "Fog of War": this.mapsController.fogOverlay,
        "Scratch map": this.mapsController.scratchLayerManager?.getLayer() || L.layerGroup(),
        Areas: this.mapsController.areasLayer || L.layerGroup(),
        Photos: this.mapsController.photoMarkers || L.layerGroup(),
        "Suggested Visits": this.getVisitCirclesLayer(),
        "Confirmed Visits": this.getConfirmedVisitCirclesLayer()
      };

      // Include Family Members layer if available
      if (window.familyMembersController?.familyMarkersLayer) {
        controlsLayer['Family Members'] = window.familyMembersController.familyMarkersLayer;
      }

      this.mapsController.layerControl = L.control.layers(
        this.mapsController.baseMaps(),
        controlsLayer
      ).addTo(this.mapsController.map);
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
      drawerButton.innerHTML = this.drawerOpen ? '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-panel-right-close-icon lucide-panel-right-close"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/><path d="m8 9 3 3-3 3"/></svg>' : '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-panel-right-open-icon lucide-panel-right-open"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/><path d="m10 15-3-3 3-3"/></svg>';
    }

    // Update the drawer content if it's being opened - but don't fetch visits automatically
    // Only show the "no data" message if there's no selection active
    if (this.drawerOpen && !this.isSelectionActive) {
      const container = document.getElementById('visits-list');
      if (container) {
        container.innerHTML = `
          <div class="text-gray-500 text-center p-4">
            <p class="mb-2">No visits data loaded</p>
            <p class="text-sm">Enable "Suggested Visits" or "Confirmed Visits" layers from the map controls to view visits.</p>
          </div>
        `;
      }
    }
    // Note: Layer visibility is now controlled by the layer control, not the drawer state
  }

  /**
   * Creates the drawer element for displaying visits
   * @returns {HTMLElement} The created drawer element
   */
  createDrawer() {
    const drawer = document.createElement('div');
    drawer.id = 'visits-drawer';
    drawer.className = 'bg-base-100 shadow-lg z-39 overflow-y-auto leaflet-drawer';

    // Add styles to make the drawer scrollable
    drawer.style.overflowY = 'auto';

    drawer.innerHTML = `
      <div class="p-3 my-2 drawer flex flex-col items-center relative">
        <button id="close-visits-drawer" class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2" title="Close panel">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-circle-x-icon lucide-circle-x"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>
        </button>
        <h2 class="text-xl font-bold mb-4 text-accent-content w-full text-center">Recent Visits</h2>
        <div id="visits-list" class="space-y-2 w-full">
          <p class="text-gray-500">Loading visits...</p>
        </div>
      </div>
    `;

    // Prevent map zoom when scrolling the drawer
    L.DomEvent.disableScrollPropagation(drawer);
    // Prevent map pan/interaction when interacting with drawer
    L.DomEvent.disableClickPropagation(drawer);

    this.map.getContainer().appendChild(drawer);

    // Add close button event listener
    const closeButton = drawer.querySelector('#close-visits-drawer');
    if (closeButton) {
      closeButton.addEventListener('click', () => {
        this.toggleDrawer();
      });
    }

    return drawer;
  }

  /**
   * Fetches visits data from the API and displays them
   */
  async fetchAndDisplayVisits() {
    try {
      console.log('fetchAndDisplayVisits called');
      // Clear any existing highlight before fetching new visits
      this.clearVisitHighlight();

      // If there's an active selection, don't perform time-based fetch
      if (this.isSelectionActive && this.selectionRect) {
        console.log('Active selection found, fetching visits in selection');
        this.fetchVisitsInSelection();
        return;
      }

      // Get current timeframe from URL parameters
      const urlParams = new URLSearchParams(window.location.search);
      const startAt = urlParams.get('start_at') || new Date().toISOString();
      const endAt = urlParams.get('end_at') || new Date().toISOString();

      console.log('Fetching visits for date range:', { startAt, endAt });
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
        console.error('Visits API response not ok:', response.status, response.statusText);
        throw new Error('Network response was not ok');
      }

      const visits = await response.json();
      console.log('Visits API response:', { count: visits.length, visits });
      this.displayVisits(visits);

      // Let the layer control manage visibility instead of drawer state
      console.log('Visit circles populated - layer control will manage visibility');
      console.log('visitCircles layer count:', this.visitCircles.getLayers().length);
      console.log('confirmedVisitCircles layer count:', this.confirmedVisitCircles.getLayers().length);

      // Check if the layers are currently enabled in the layer control and ensure they're visible
      const layerControl = this.map._layers;
      let suggestedVisitsEnabled = false;
      let confirmedVisitsEnabled = false;

      // Check layer control state
      Object.values(layerControl || {}).forEach(layer => {
        if (layer.name === 'Suggested Visits' && this.map.hasLayer(layer.layer)) {
          suggestedVisitsEnabled = true;
        }
        if (layer.name === 'Confirmed Visits' && this.map.hasLayer(layer.layer)) {
          confirmedVisitsEnabled = true;
        }
      });

      console.log('Layer control state:', { suggestedVisitsEnabled, confirmedVisitsEnabled });
    } catch (error) {
      console.error('Error fetching visits:', error);
      const container = document.getElementById('visits-list');
      if (container) {
        container.innerHTML = '<p class="text-red-500">Error loading visits</p>';
      }
    }
  }

  /**
   * Creates visit circles on the map (independent of drawer UI)
   * @param {Array} visits - Array of visit objects
   */
  createMapCircles(visits) {
    if (!visits || visits.length === 0) {
      console.log('No visits to create circles for');
      return;
    }

    // Clear existing visit circles
    console.log('Clearing existing visit circles');
    this.visitCircles.clearLayers();
    this.confirmedVisitCircles.clearLayers();

    let suggestedCount = 0;
    let confirmedCount = 0;

    // Draw circles for all visits
    visits
      .filter(visit => visit.status !== 'declined')
      .forEach(visit => {
        if (visit.place?.latitude && visit.place?.longitude) {
          const isConfirmed = visit.status === 'confirmed';
          const isSuggested = visit.status === 'suggested';

          console.log('Creating circle for visit:', {
            id: visit.id,
            status: visit.status,
            lat: visit.place.latitude,
            lng: visit.place.longitude,
            isConfirmed,
            isSuggested
          });

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
            confirmedCount++;
            console.log('Added confirmed visit circle to layer');
          } else {
            this.visitCircles.addLayer(circle);
            suggestedCount++;
            console.log('Added suggested visit circle to layer');
          }

          // Attach click event to the circle
          circle.on('click', () => this.fetchPossiblePlaces(visit));
        } else {
          console.warn('Visit missing coordinates:', visit);
        }
      });

    console.log('Visit circles created:', { suggestedCount, confirmedCount });
  }

  /**
   * Displays visits on the map and in the drawer
   * @param {Array} visits - Array of visit objects
   */
  displayVisits(visits) {
    // Always create map circles regardless of drawer state
    this.createMapCircles(visits);

    // Update drawer UI only if container exists
    const container = document.getElementById('visits-list');
    if (!container) {
      console.log('No visits-list container found - skipping drawer UI update');
      return;
    }

    // Save the current state of collapsible sections before updating
    const dataSectionOpen = document.querySelector('#data-section-collapse')?.open || false;
    const visitsSectionOpen = document.querySelector('#visits-section-collapse')?.open || false;

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

    // Map circles are handled by createMapCircles() - just generate drawer HTML
    const visitsHtml = visits
      // Filter out declined visits
      .filter(visit => visit.status !== 'declined')
      .map(visit => {
        const startDate = new Date(visit.started_at);
        const endDate = new Date(visit.ended_at);
        const tzOptions = { timeZone: this.timezone };
        const isSameDay = startDate.toLocaleDateString(undefined, tzOptions) === endDate.toLocaleDateString(undefined, tzOptions);

        let timeDisplay;
        if (isSameDay) {
          timeDisplay = `
            ${startDate.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: this.timezone })},
            ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: this.timezone })} -
            ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: this.timezone })}
          `;
        } else {
          timeDisplay = `
            ${startDate.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: this.timezone })},
            ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: this.timezone })} -
            ${endDate.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: this.timezone })},
            ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: this.timezone })}
          `;
        }

        const durationText = this.formatDuration(visit.duration * 60);

        // Add opacity class for suggested visits
        const bgClass = visit.status === 'suggested' ? 'bg-neutral border-dashed border-2 border-sky-500' : 'bg-base-200';
        const visitStyle = visit.status === 'suggested' ? 'border: 2px dashed #60a5fa;' : '';

        return `
          <div class="w-full p-3 mt-2 rounded-lg hover:bg-base-300 transition-colors visit-item relative ${bgClass}"
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

    // Wrap visits in a collapsible section
    const visitsSection = visits && visits.length > 0 ? `
      <details id="visits-section-collapse" class="collapse collapse-arrow bg-base-100 rounded-lg mb-4 shadow-sm">
        <summary class="collapse-title text-lg font-bold">
          Visits (${visits.filter(v => v.status !== 'declined').length})
        </summary>
        <div class="collapse-content">
          ${visitsHtml}
        </div>
      </details>
    ` : '';

    // Combine date summary and visits HTML
    container.innerHTML = dateGroupsHtml + visitsSection;

    // Restore the state of collapsible sections
    const dataSection = document.querySelector('#data-section-collapse');
    const visitsSection2 = document.querySelector('#visits-section-collapse');

    if (dataSection && dataSectionOpen) {
      dataSection.open = true;
    }
    if (visitsSection2 && visitsSectionOpen) {
      visitsSection2.open = true;
    }

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

        // Add cancel selection button
        const cancelButton = document.createElement('button');
        cancelButton.className = 'btn btn-xs btn-neutral w-full mt-2';
        cancelButton.textContent = 'Cancel Selection';
        cancelButton.addEventListener('click', () => {
          // Uncheck all checkboxes
          checkedBoxes.forEach(checkbox => {
            checkbox.checked = false;
          });
          // Update UI to remove action buttons
          this.updateMergeUI(container);
        });

        // Add elements to container
        actionsContainer.appendChild(buttonGrid);
        actionsContainer.appendChild(selectionText);
        actionsContainer.appendChild(cancelButton);

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
          ${startDate.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })},
          ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
          ${endDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })}
        `;
      } else {
        dateTimeDisplay = `
          ${startDate.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })},
          ${startDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })} -
          ${endDate.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })},
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
        <div style="min-width: 280px;">
          <h3 class="text-base font-semibold mb-3">${dateTimeDisplay.trim()}</h3>

          <div class="space-y-1 mb-4 text-sm">
            <div>Duration: ${durationText}</div>
            <div class="${statusColorClass} font-semibold">Status: ${visit.status.charAt(0).toUpperCase() + visit.status.slice(1)}</div>
            <div class="text-xs opacity-60 font-mono">${visit.place.latitude}, ${visit.place.longitude}</div>
          </div>

          <form class="visit-name-form space-y-3" data-visit-id="${visit.id}">
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Visit Name:</span>
              </label>
              <input type="text"
                     class="input input-bordered w-full"
                     value="${defaultName}"
                     placeholder="Enter visit name">
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Location:</span>
              </label>
              <select class="select select-bordered w-full" name="place">
                ${possiblePlaces.length > 0 ? possiblePlaces.map(place => `
                  <option value="${place.id}" ${place.id === visit.place.id ? 'selected' : ''}>
                    ${place.name}
                  </option>
                `).join('') : `
                  <option value="${visit.place.id}" selected>
                    ${visit.place.name || 'Current Location'}
                  </option>
                `}
              </select>
            </div>

            <div class="grid grid-cols-3 gap-2">
              <button type="submit" class="btn btn-primary btn-sm">
                Save
              </button>
              ${visit.status !== 'confirmed' ? `
                <button type="button" class="btn btn-success btn-sm confirm-visit" data-id="${visit.id}">
                  Confirm
                </button>
                <button type="button" class="btn btn-error btn-sm decline-visit" data-id="${visit.id}">
                  Decline
                </button>
              ` : '<div class="col-span-2"></div>'}
            </div>

            <button type="button" class="btn btn-outline btn-error btn-sm w-full delete-visit" data-id="${visit.id}">
              Delete Visit
            </button>
          </form>
        </div>
      `;

      // Create and store the popup
      const popup = L.popup({
        closeButton: true,
        closeOnClick: true,
        autoClose: true,
        closeOnEscapeKey: true,
        maxWidth: 420, // Set maximum width
        minWidth: 320, // Set minimum width
        className: 'visit-popup' // Add custom class for additional styling
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

        // Validate that we have a valid place_id
        if (!selectedPlaceId || selectedPlaceId === '') {
          showFlashMessage('error', 'Please select a valid location');
          return;
        }

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
      const deleteBtn = form.querySelector('.delete-visit');

      confirmBtn?.addEventListener('click', (event) => this.handleStatusChange(event, visit.id, 'confirmed'));
      declineBtn?.addEventListener('click', (event) => this.handleStatusChange(event, visit.id, 'declined'));
      deleteBtn?.addEventListener('click', (event) => this.handleDeleteVisit(event, visit.id));
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
   * Handles deletion of a visit with confirmation
   * @param {Event} event - The click event
   * @param {string} visitId - The visit ID to delete
   */
  async handleDeleteVisit(event, visitId) {
    event.preventDefault();
    event.stopPropagation();

    // Show confirmation dialog
    const confirmDelete = confirm('Are you sure you want to delete this visit? This action cannot be undone.');

    if (!confirmDelete) {
      return;
    }

    try {
      const response = await fetch(`/api/v1/visits/${visitId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
        }
      });

      if (response.ok) {
        // Close the popup
        if (this.currentPopup) {
          this.map.closePopup(this.currentPopup);
          this.currentPopup = null;
        }

        // Refresh the visits list
        this.fetchAndDisplayVisits();
        showFlashMessage('notice', 'Visit deleted successfully');
      } else {
        const errorData = await response.json();
        const errorMessage = errorData.error || 'Failed to delete visit';
        showFlashMessage('error', errorMessage);
      }
    } catch (error) {
      console.error('Error deleting visit:', error);
      showFlashMessage('error', 'Failed to delete visit');
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
