/**
 * HexagonGrid - Manages hexagonal grid overlay on Leaflet maps
 * Provides efficient loading and rendering of hexagon tiles based on viewport
 */
export class HexagonGrid {
  constructor(map, options = {}) {
    this.map = map;
    this.options = {
      apiEndpoint: '/api/v1/maps/hexagons',
      style: {
        fillColor: '#3388ff',
        fillOpacity: 0.1,
        color: '#3388ff',
        weight: 1,
        opacity: 0.5
      },
      debounceDelay: 300, // ms to wait before loading new hexagons
      maxZoom: 18, // Don't show hexagons beyond this zoom level
      minZoom: 8,  // Don't show hexagons below this zoom level
      ...options
    };
    
    this.hexagonLayer = null;
    this.loadingController = null; // For aborting requests
    this.lastBounds = null;
    this.isVisible = false;
    
    this.init();
  }

  init() {
    // Create the hexagon layer group
    this.hexagonLayer = L.layerGroup();
    
    // Bind map events
    this.map.on('moveend', this.debounce(this.onMapMove.bind(this), this.options.debounceDelay));
    this.map.on('zoomend', this.onZoomChange.bind(this));
    
    // Initial load if within zoom range
    if (this.shouldShowHexagons()) {
      this.show();
    }
  }

  /**
   * Show the hexagon grid overlay
   */
  show() {
    if (!this.isVisible) {
      this.isVisible = true;
      if (this.shouldShowHexagons()) {
        this.hexagonLayer.addTo(this.map);
        this.loadHexagons();
      }
    }
  }

  /**
   * Hide the hexagon grid overlay
   */
  hide() {
    if (this.isVisible) {
      this.isVisible = false;
      this.hexagonLayer.remove();
      this.cancelPendingRequest();
    }
  }

  /**
   * Toggle visibility of hexagon grid
   */
  toggle() {
    if (this.isVisible) {
      this.hide();
    } else {
      this.show();
    }
  }

  /**
   * Check if hexagons should be displayed at current zoom level
   */
  shouldShowHexagons() {
    const zoom = this.map.getZoom();
    return zoom >= this.options.minZoom && zoom <= this.options.maxZoom;
  }

  /**
   * Handle map move events
   */
  onMapMove() {
    if (!this.isVisible || !this.shouldShowHexagons()) {
      return;
    }

    const currentBounds = this.map.getBounds();
    
    // Only reload if bounds have changed significantly
    if (this.boundsChanged(currentBounds)) {
      this.loadHexagons();
    }
  }

  /**
   * Handle zoom change events
   */
  onZoomChange() {
    if (!this.isVisible) {
      return;
    }

    if (this.shouldShowHexagons()) {
      // Show hexagons and load for new zoom level
      if (!this.map.hasLayer(this.hexagonLayer)) {
        this.hexagonLayer.addTo(this.map);
      }
      this.loadHexagons();
    } else {
      // Hide hexagons when zoomed too far in/out
      this.hexagonLayer.remove();
      this.cancelPendingRequest();
    }
  }

  /**
   * Check if bounds have changed enough to warrant reloading
   */
  boundsChanged(newBounds) {
    if (!this.lastBounds) {
      return true;
    }

    const threshold = 0.1; // 10% change threshold
    const oldArea = this.getBoundsArea(this.lastBounds);
    const newArea = this.getBoundsArea(newBounds);
    const intersection = this.getBoundsIntersection(this.lastBounds, newBounds);
    const intersectionRatio = intersection / Math.min(oldArea, newArea);

    return intersectionRatio < (1 - threshold);
  }

  /**
   * Calculate approximate area of bounds
   */
  getBoundsArea(bounds) {
    const sw = bounds.getSouthWest();
    const ne = bounds.getNorthEast();
    return (ne.lat - sw.lat) * (ne.lng - sw.lng);
  }

  /**
   * Calculate intersection area between two bounds
   */
  getBoundsIntersection(bounds1, bounds2) {
    const sw1 = bounds1.getSouthWest();
    const ne1 = bounds1.getNorthEast();
    const sw2 = bounds2.getSouthWest();
    const ne2 = bounds2.getNorthEast();

    const left = Math.max(sw1.lng, sw2.lng);
    const right = Math.min(ne1.lng, ne2.lng);
    const bottom = Math.max(sw1.lat, sw2.lat);
    const top = Math.min(ne1.lat, ne2.lat);

    if (left < right && bottom < top) {
      return (right - left) * (top - bottom);
    }
    return 0;
  }

  /**
   * Load hexagons for current viewport
   */
  async loadHexagons() {
    // Cancel any pending request
    this.cancelPendingRequest();

    const bounds = this.map.getBounds();
    this.lastBounds = bounds;

    // Create new AbortController for this request
    this.loadingController = new AbortController();

    try {
      const params = new URLSearchParams({
        min_lon: bounds.getWest(),
        min_lat: bounds.getSouth(),
        max_lon: bounds.getEast(),
        max_lat: bounds.getNorth()
      });

      const response = await fetch(`${this.options.apiEndpoint}&${params}`, {
        signal: this.loadingController.signal,
        headers: {
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const geojsonData = await response.json();
      
      // Clear existing hexagons and add new ones
      this.clearHexagons();
      this.addHexagonsToMap(geojsonData);

    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error('Failed to load hexagons:', error);
        // Optionally show user-friendly error message
      }
    } finally {
      this.loadingController = null;
    }
  }

  /**
   * Cancel pending hexagon loading request
   */
  cancelPendingRequest() {
    if (this.loadingController) {
      this.loadingController.abort();
      this.loadingController = null;
    }
  }

  /**
   * Clear existing hexagons from the map
   */
  clearHexagons() {
    this.hexagonLayer.clearLayers();
  }

  /**
   * Add hexagons to the map from GeoJSON data
   */
  addHexagonsToMap(geojsonData) {
    if (!geojsonData.features || geojsonData.features.length === 0) {
      return;
    }

    const geoJsonLayer = L.geoJSON(geojsonData, {
      style: () => this.options.style,
      onEachFeature: (feature, layer) => {
        // Add hover effects
        layer.on({
          mouseover: (e) => this.onHexagonMouseOver(e),
          mouseout: (e) => this.onHexagonMouseOut(e),
          click: (e) => this.onHexagonClick(e, feature)
        });
      }
    });

    geoJsonLayer.addTo(this.hexagonLayer);
  }

  /**
   * Handle hexagon mouseover event
   */
  onHexagonMouseOver(e) {
    const layer = e.target;
    layer.setStyle({
      fillOpacity: 0.2,
      weight: 2
    });
  }

  /**
   * Handle hexagon mouseout event
   */
  onHexagonMouseOut(e) {
    const layer = e.target;
    layer.setStyle(this.options.style);
  }

  /**
   * Handle hexagon click event
   */
  onHexagonClick(e, feature) {
    // Override this method to add custom click behavior
    console.log('Hexagon clicked:', feature, 'at coordinates:', e.latlng);
  }

  /**
   * Update hexagon style
   */
  updateStyle(newStyle) {
    this.options.style = { ...this.options.style, ...newStyle };
    
    // Update existing hexagons
    this.hexagonLayer.eachLayer((layer) => {
      if (layer.setStyle) {
        layer.setStyle(this.options.style);
      }
    });
  }

  /**
   * Destroy the hexagon grid and clean up
   */
  destroy() {
    this.hide();
    this.map.off('moveend');
    this.map.off('zoomend');
    this.hexagonLayer = null;
    this.lastBounds = null;
  }

  /**
   * Simple debounce utility
   */
  debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  }
}

/**
 * Create and return a new HexagonGrid instance
 */
export function createHexagonGrid(map, options = {}) {
  return new HexagonGrid(map, options);
}

// Default export
export default HexagonGrid;