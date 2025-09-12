import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import { createHexagonGrid } from "../maps/hexagon_grid";

export default class extends Controller {
  static targets = ["container"];
  static values = { 
    year: Number, 
    month: Number, 
    uuid: String,
    dataBounds: Object
  };

  connect() {
    this.initializeMap();
    this.loadHexagons();
  }

  disconnect() {
    if (this.hexagonGrid) {
      this.hexagonGrid.destroy();
    }
    if (this.map) {
      this.map.remove();
    }
  }

  initializeMap() {
    // Initialize map with interactive controls enabled
    this.map = L.map(this.element, {
      zoomControl: true,
      scrollWheelZoom: true,
      doubleClickZoom: true,
      touchZoom: true,
      dragging: true,
      keyboard: false
    });

    // Add tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors',
      maxZoom: 15
    }).addTo(this.map);

    // Default view
    this.map.setView([40.0, -100.0], 4);
  }

  async loadHexagons() {
    try {
      // Calculate date range for the month
      const startDate = new Date(this.yearValue, this.monthValue - 1, 1);
      const endDate = new Date(this.yearValue, this.monthValue, 0, 23, 59, 59);

      // Use server-provided data bounds
      const dataBounds = this.dataBoundsValue;
      
      if (dataBounds && dataBounds.point_count > 0) {
        // Set map view to data bounds BEFORE creating hexagon grid
        this.map.fitBounds([
          [dataBounds.min_lat, dataBounds.min_lng],
          [dataBounds.max_lat, dataBounds.max_lng]
        ], { padding: [20, 20] });
        
        // Wait for the map to finish fitting bounds
        await new Promise(resolve => {
          this.map.once('moveend', resolve);
          // Fallback timeout in case moveend doesn't fire
          setTimeout(resolve, 1000);
        });
      }

      // Create hexagon grid with API endpoint for public sharing
      // Note: We need to prevent automatic showing during init
      this.hexagonGrid = createHexagonGrid(this.map, {
        apiEndpoint: '/api/v1/maps/hexagons',
        style: {
          fillColor: '#3388ff',
          fillOpacity: 0.3,
          color: '#3388ff',
          weight: 1,
          opacity: 0.7
        },
        debounceDelay: 300,
        maxZoom: 15,
        minZoom: 4
      });

      // Force hide immediately after creation to prevent auto-showing
      this.hexagonGrid.hide();

      // Disable all dynamic behavior by removing event listeners
      this.map.off('moveend');
      this.map.off('zoomend');

      // Load hexagons only once on page load (static behavior)
      if (dataBounds && dataBounds.point_count > 0) {
        await this.loadStaticHexagons();
      } else {
        console.warn('No data bounds or points available - not showing hexagons');
      }

      // Hide loading indicator
      const loadingElement = document.getElementById('map-loading');
      if (loadingElement) {
        loadingElement.style.display = 'none';
      }

    } catch (error) {
      console.error('Error initializing hexagon grid:', error);
      
      // Hide loading indicator even on error
      const loadingElement = document.getElementById('map-loading');
      if (loadingElement) {
        loadingElement.style.display = 'none';
      }
    }
  }

  async loadStaticHexagons() {
    console.log('🔄 Loading static hexagons for public sharing...');
    
    try {
      // Calculate date range for the month
      const startDate = new Date(this.yearValue, this.monthValue - 1, 1);
      const endDate = new Date(this.yearValue, this.monthValue, 0, 23, 59, 59);
      
      // Use the full data bounds for hexagon request (not current map viewport)
      const dataBounds = this.dataBoundsValue;
      
      const params = new URLSearchParams({
        min_lon: dataBounds.min_lng,
        min_lat: dataBounds.min_lat,
        max_lon: dataBounds.max_lng,
        max_lat: dataBounds.max_lat,
        hex_size: 1000, // Fixed 1km hexagons
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString(),
        uuid: this.uuidValue
      });

      const url = `/api/v1/maps/hexagons?${params}`;
      console.log('📍 Fetching static hexagons from:', url);
      
      const response = await fetch(url, {
        headers: {
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('Hexagon API error:', response.status, response.statusText, errorText);
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const geojsonData = await response.json();
      console.log(`✅ Loaded ${geojsonData.features?.length || 0} hexagons`);

      // Add hexagons directly to map as a static layer
      if (geojsonData.features && geojsonData.features.length > 0) {
        this.addStaticHexagonsToMap(geojsonData);
      }

    } catch (error) {
      console.error('Failed to load static hexagons:', error);
    }
  }

  addStaticHexagonsToMap(geojsonData) {
    // Calculate max point count for color scaling
    const maxPoints = Math.max(...geojsonData.features.map(f => f.properties.point_count));

    const staticHexagonLayer = L.geoJSON(geojsonData, {
      style: (feature) => this.styleHexagon(feature, maxPoints),
      onEachFeature: (feature, layer) => {
        // Add popup with statistics
        const props = feature.properties;
        const popupContent = this.buildPopupContent(props);
        layer.bindPopup(popupContent);

        // Add hover effects
        layer.on({
          mouseover: (e) => this.onHexagonMouseOver(e),
          mouseout: (e) => this.onHexagonMouseOut(e)
        });
      }
    });

    staticHexagonLayer.addTo(this.map);
  }

  styleHexagon(feature, maxPoints) {
    const props = feature.properties;
    const pointCount = props.point_count || 0;

    // Calculate opacity based on point density
    const opacity = 0.2 + (pointCount / maxPoints) * 0.6;
    const color = '#3388ff';

    return {
      fillColor: color,
      fillOpacity: opacity,
      color: color,
      weight: 1,
      opacity: opacity + 0.2
    };
  }

  buildPopupContent(props) {
    const startDate = props.earliest_point ? new Date(props.earliest_point).toLocaleDateString() : 'N/A';
    const endDate = props.latest_point ? new Date(props.latest_point).toLocaleDateString() : 'N/A';

    return `
      <div style="font-size: 12px; line-height: 1.4;">
        <h4 style="margin: 0 0 8px 0; color: #2c5aa0;">Hexagon Stats</h4>
        <strong>Points:</strong> ${props.point_count || 0}<br>
        <strong>Density:</strong> ${props.density || 0} pts/km²<br>
        ${props.avg_speed ? `<strong>Avg Speed:</strong> ${props.avg_speed} km/h<br>` : ''}
        ${props.avg_battery ? `<strong>Avg Battery:</strong> ${props.avg_battery}%<br>` : ''}
        <strong>Date Range:</strong><br>
        <small>${startDate} - ${endDate}</small>
      </div>
    `;
  }

  onHexagonMouseOver(e) {
    const layer = e.target;
    // Store original style before changing
    if (!layer._originalStyle) {
      layer._originalStyle = {
        fillOpacity: layer.options.fillOpacity,
        weight: layer.options.weight,
        opacity: layer.options.opacity
      };
    }
    
    layer.setStyle({
      fillOpacity: 0.8,
      weight: 2,
      opacity: 1.0
    });
  }

  onHexagonMouseOut(e) {
    const layer = e.target;
    // Reset to stored original style
    if (layer._originalStyle) {
      layer.setStyle(layer._originalStyle);
    }
  }

  // getDataBounds method removed - now using server-provided data bounds
}