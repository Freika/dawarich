import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import { showFlashMessage } from "../maps/helpers";

export default class extends Controller {
  static targets = [];

  static values = {
    features: Object,
    userTheme: String
  }

  connect() {
    console.log("Family members controller connected");

    // Wait for maps controller to be ready
    this.waitForMap();
  }

  disconnect() {
    this.cleanup();
    console.log("Family members controller disconnected");
  }

  waitForMap() {
    // Find the maps controller element
    const mapElement = document.querySelector('[data-controller*="maps"]');
    if (!mapElement) {
      console.warn('Maps controller element not found');
      return;
    }

    // Wait for the maps controller to be initialized
    const checkMapReady = () => {
      if (window.mapsController && window.mapsController.map) {
        this.initializeFamilyFeatures();
      } else {
        setTimeout(checkMapReady, 100);
      }
    };

    checkMapReady();
  }

  initializeFamilyFeatures() {
    this.map = window.mapsController.map;

    if (!this.map) {
      console.warn('Map not available for family members controller');
      return;
    }

    // Initialize family member markers layer
    this.familyMarkersLayer = L.layerGroup();
    this.familyMemberLocations = []; // Initialize as empty, will be fetched via API

    // Add to layer control immediately (layer will be empty until data is fetched)
    this.addToLayerControl();

    // Listen for family data updates
    this.setupEventListeners();
  }

  createFamilyMarkers() {
    // Clear existing family markers
    if (this.familyMarkersLayer) {
      this.familyMarkersLayer.clearLayers();
    }

    // Only proceed if family feature is enabled and we have family member locations
    if (!this.featuresValue.family ||
        !this.familyMemberLocations ||
        this.familyMemberLocations.length === 0) {
      return;
    }

    const bounds = [];

    this.familyMemberLocations.forEach((location) => {
      if (!location || !location.latitude || !location.longitude) {
        return;
      }

      // Get the first letter of the email or use '?' as fallback
      const emailInitial = location.email_initial || location.email?.charAt(0)?.toUpperCase() || '?';

      // Create a distinct marker for family members with email initial
      const familyMarker = L.marker([location.latitude, location.longitude], {
        icon: L.divIcon({
          html: `<div style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 14px; font-weight: bold; font-family: system-ui, -apple-system, sans-serif;">${emailInitial}</div>`,
          iconSize: [24, 24],
          iconAnchor: [12, 12],
          className: 'family-member-marker'
        })
      });

      // Format timestamp for display
      const lastSeen = new Date(location.updated_at).toLocaleString();

      // Create small tooltip that shows automatically
      const tooltipContent = this.createTooltipContent(lastSeen);
      const tooltip = familyMarker.bindTooltip(tooltipContent, {
        permanent: true,
        direction: 'top',
        offset: [0, -12],
        className: 'family-member-tooltip'
      });

      // Create detailed popup that shows on click
      const popupContent = this.createPopupContent(location, lastSeen);
      familyMarker.bindPopup(popupContent);

      // Hide tooltip when popup opens, show when popup closes
      familyMarker.on('popupopen', () => {
        familyMarker.closeTooltip();
      });
      familyMarker.on('popupclose', () => {
        familyMarker.openTooltip();
      });

      this.familyMarkersLayer.addLayer(familyMarker);

      // Add to bounds array for auto-zoom
      bounds.push([location.latitude, location.longitude]);
    });

    // Store bounds for later use
    this.familyMemberBounds = bounds;
  }

  createTooltipContent(lastSeen) {
    return `Last updated: ${lastSeen}`;
  }

  createPopupContent(location, lastSeen) {
    const isDark = this.userThemeValue === 'dark';
    const bgColor = isDark ? '#1f2937' : '#ffffff';
    const textColor = isDark ? '#f9fafb' : '#111827';
    const mutedColor = isDark ? '#9ca3af' : '#6b7280';

    const emailInitial = location.email_initial || location.email?.charAt(0)?.toUpperCase() || '?';

    return `
      <div class="family-member-popup" style="background-color: ${bgColor}; color: ${textColor}; padding: 12px; border-radius: 8px; min-width: 220px;">
        <h3 style="margin: 0 0 12px 0; color: #10B981; font-size: 15px; font-weight: bold; display: flex; align-items: center; gap: 8px;">
          <span style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: bold;">${emailInitial}</span>
          Family Member
        </h3>
        <p style="margin: 0 0 8px 0; font-size: 13px;">
          <strong>Email:</strong> ${location.email || 'Unknown'}
        </p>
        <p style="margin: 0 0 8px 0; font-size: 13px;">
          <strong>Coordinates:</strong><br/>
          ${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}
        </p>
        <p style="margin: 0; font-size: 12px; color: ${mutedColor}; padding-top: 8px; border-top: 1px solid ${isDark ? '#374151' : '#e5e7eb'};">
          <strong>Last updated:</strong> ${lastSeen}
        </p>
      </div>
    `;
  }

  addToLayerControl() {
    // Add family markers layer to the maps controller's layer control
    if (window.mapsController && window.mapsController.layerControl && this.familyMarkersLayer) {
      // We need to recreate the layer control to include our new layer
      this.updateMapsControllerLayerControl();
    }
  }

  updateMapsControllerLayerControl() {
    const mapsController = window.mapsController;
    if (!mapsController || typeof mapsController.updateLayerControl !== 'function') return;

    // Use the maps controller's helper method to update layer control
    mapsController.updateLayerControl({
      "Family Members": this.familyMarkersLayer
    });
  }

  setupEventListeners() {
    // Listen for family data updates (for real-time updates in the future)
    document.addEventListener('family:locations:updated', (event) => {
      this.familyMemberLocations = event.detail.locations;
      this.createFamilyMarkers();
    });

    // Listen for theme changes
    document.addEventListener('theme:changed', (event) => {
      this.userThemeValue = event.detail.theme;
      // Recreate popups with new theme
      this.createFamilyMarkers();
    });

    // Listen for layer control events
    this.setupLayerControlEvents();
  }

  setupLayerControlEvents() {
    if (!this.map) return;

    // Listen for when the Family Members layer is added
    this.map.on('overlayadd', (event) => {
      if (event.name === 'Family Members' && event.layer === this.familyMarkersLayer) {
        console.log('Family Members layer enabled - refreshing locations and zooming to fit');
        this.refreshFamilyLocations();

        // Zoom to show all family members
        this.zoomToFitAllMembers();

        // Set up periodic refresh while layer is active
        this.startPeriodicRefresh();
      }
    });

    // Listen for when the Family Members layer is removed
    this.map.on('overlayremove', (event) => {
      if (event.name === 'Family Members' && event.layer === this.familyMarkersLayer) {
        // Stop periodic refresh when layer is disabled
        this.stopPeriodicRefresh();
      }
    });
  }

  zoomToFitAllMembers() {
    if (!this.familyMemberBounds || this.familyMemberBounds.length === 0) {
      return;
    }

    // If there's only one member, center on them with a reasonable zoom
    if (this.familyMemberBounds.length === 1) {
      this.map.setView(this.familyMemberBounds[0], 13);
      return;
    }

    // For multiple members, fit bounds to show all of them
    const bounds = L.latLngBounds(this.familyMemberBounds);
    this.map.fitBounds(bounds, {
      padding: [50, 50], // Add padding around the edges
      maxZoom: 15 // Don't zoom in too close
    });
  }

  startPeriodicRefresh() {
    // Clear any existing refresh interval
    this.stopPeriodicRefresh();

    // Refresh family locations every 30 seconds while layer is active
    this.refreshInterval = setInterval(() => {
      if (this.map && this.map.hasLayer(this.familyMarkersLayer)) {
        this.refreshFamilyLocations();
      } else {
        // Layer is no longer active, stop refreshing
        this.stopPeriodicRefresh();
      }
    }, 30000); // 30 seconds
  }

  stopPeriodicRefresh() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  // Method to manually update family member locations (for API calls)
  updateFamilyLocations(locations) {
    this.familyMemberLocations = locations;
    this.createFamilyMarkers();

    // Dispatch event for other controllers that might be interested
    document.dispatchEvent(new CustomEvent('family:locations:updated', {
      detail: { locations: locations }
    }));
  }

  // Method to refresh family locations from API
  async refreshFamilyLocations() {
    if (!window.mapsController?.apiKey) {
      console.warn('API key not available for family locations refresh');
      return;
    }

    try {
      const response = await fetch(`/api/v1/families/locations?api_key=${window.mapsController.apiKey}`, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }
      });

      if (!response.ok) {
        if (response.status === 403) {
          console.warn('Family feature not enabled or user not in family');
          return;
        }
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      this.updateFamilyLocations(data.locations || []);

      // Show user feedback if this was a manual refresh
      if (this.showUserFeedback) {
        const count = data.locations?.length || 0;
        this.showFlashMessageToUser('notice', `Family locations updated (${count} members)`);
        this.showUserFeedback = false; // Reset flag
      }

    } catch (error) {
      console.error('Error refreshing family locations:', error);

      // Show error to user if this was a manual refresh
      if (this.showUserFeedback) {
        this.showFlashMessageToUser('error', 'Failed to refresh family locations');
        this.showUserFeedback = false; // Reset flag
      }
    }
  }

  // Helper method to show flash messages using the imported helper
  showFlashMessageToUser(type, message) {
    showFlashMessage(type, message);
  }

  // Method for manual refresh with user feedback
  async manualRefreshFamilyLocations() {
    this.showUserFeedback = true; // Enable user feedback for this refresh
    await this.refreshFamilyLocations();
  }

  cleanup() {
    // Stop periodic refresh
    this.stopPeriodicRefresh();

    // Remove family markers layer from map if it exists
    if (this.familyMarkersLayer && this.map && this.map.hasLayer(this.familyMarkersLayer)) {
      this.map.removeLayer(this.familyMarkersLayer);
    }

    // Remove map event listeners
    if (this.map) {
      this.map.off('overlayadd');
      this.map.off('overlayremove');
    }

    // Remove document event listeners
    document.removeEventListener('family:locations:updated', this.handleLocationUpdates);
    document.removeEventListener('theme:changed', this.handleThemeChange);
  }

  // Expose layer for external access
  getFamilyMarkersLayer() {
    return this.familyMarkersLayer;
  }

  // Check if family features are enabled
  isFamilyFeatureEnabled() {
    return this.featuresValue.family === true;
  }

  // Get family marker count
  getFamilyMemberCount() {
    return this.familyMemberLocations ? this.familyMemberLocations.length : 0;
  }
}