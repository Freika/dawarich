import L from "leaflet";
import { createAllMapLayers } from "../maps/layers";
import BaseController from "./base_controller";

export default class extends BaseController {
  static targets = ["container"];
  static values = {
    year: Number,
    month: Number,
    uuid: String,
    dataBounds: Object,
    hexagonsAvailable: Boolean,
    selfHosted: String
  };

  connect() {
    super.connect();
    console.log('🏁 Controller connected - loading overlay should be visible');
    this.selfHosted = this.selfHostedValue || 'false';
    this.currentHexagonLayer = null;
    this.initializeMap();
    this.loadHexagons();
  }

  disconnect() {
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

    // Add dynamic tile layer based on self-hosted setting
    this.addMapLayers();

    // Default view with higher zoom level for better hexagon detail
    this.map.setView([40.0, -100.0], 9);
  }

  addMapLayers() {
    try {
      // Use appropriate default layer based on self-hosted mode
      const selectedLayerName = this.selfHosted === "true" ? "OpenStreetMap" : "Light";
      const maps = createAllMapLayers(this.map, selectedLayerName, this.selfHosted, 'dark');

      // If no layers were created, fall back to OSM
      if (Object.keys(maps).length === 0) {
        console.warn('No map layers available, falling back to OSM');
        this.addFallbackOSMLayer();
      }
    } catch (error) {
      console.error('Error creating map layers:', error);
      console.log('Falling back to OSM tile layer');
      this.addFallbackOSMLayer();
    }
  }

  addFallbackOSMLayer() {
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors',
      maxZoom: 15
    }).addTo(this.map);
  }

  async loadHexagons() {
    console.log('🎯 loadHexagons started - checking overlay state');
    const initialLoadingElement = document.getElementById('map-loading');
    console.log('📊 Initial overlay display:', initialLoadingElement?.style.display || 'default');

    try {
      // Use server-provided data bounds
      const dataBounds = this.dataBoundsValue;

      if (dataBounds && dataBounds.point_count > 0) {
        // Set map view to data bounds BEFORE creating hexagon grid
        this.map.fitBounds([
          [dataBounds.min_lat, dataBounds.min_lng],
          [dataBounds.max_lat, dataBounds.max_lng]
        ], { padding: [20, 20] });

        // Wait for the map to finish fitting bounds
        console.log('⏳ About to wait for map moveend - overlay should still be visible');
        await new Promise(resolve => {
          this.map.once('moveend', resolve);
          // Fallback timeout in case moveend doesn't fire
          setTimeout(resolve, 1000);
        });
        console.log('✅ Map fitBounds complete - checking overlay state');
        const afterFitBoundsElement = document.getElementById('map-loading');
        console.log('📊 After fitBounds overlay display:', afterFitBoundsElement?.style.display || 'default');
      }

      console.log('🎯 Public sharing: using manual hexagon loading');
      console.log('🔍 Debug values:');
      console.log('  dataBounds:', dataBounds);
      console.log('  point_count:', dataBounds?.point_count);
      console.log('  hexagonsAvailableValue:', this.hexagonsAvailableValue);
      console.log('  hexagonsAvailableValue type:', typeof this.hexagonsAvailableValue);

      // Load hexagons only if they are pre-calculated and data exists
      if (dataBounds && dataBounds.point_count > 0 && this.hexagonsAvailableValue) {
        await this.loadStaticHexagons();
      } else {
        if (!this.hexagonsAvailableValue) {
          console.log('📋 No pre-calculated hexagons available for public sharing - skipping hexagon loading');
        } else {
          console.warn('⚠️ No data bounds or points available - not showing hexagons');
        }
        // Hide loading indicator if no hexagons to load
        const loadingElement = document.getElementById('map-loading');
        if (loadingElement) {
          loadingElement.style.display = 'none';
        }
      }

    } catch (error) {
      console.error('Error initializing hexagon grid:', error);

      // Hide loading indicator on initialization error
      const loadingElement = document.getElementById('map-loading');
      if (loadingElement) {
        loadingElement.style.display = 'none';
      }
    }

    // Do NOT hide loading overlay here - let loadStaticHexagons() handle it completely
  }

  async loadStaticHexagons() {
    console.log('🔄 Loading static hexagons for public sharing...');

    // Ensure loading overlay is visible and disable map interaction
    const loadingElement = document.getElementById('map-loading');
    console.log('🔍 Loading element found:', !!loadingElement);
    if (loadingElement) {
      loadingElement.style.display = 'flex';
      loadingElement.style.visibility = 'visible';
      loadingElement.style.zIndex = '9999';
      console.log('👁️ Loading overlay ENSURED visible - should be visible now');
    }

    // Disable map interaction during loading
    this.map.dragging.disable();
    this.map.touchZoom.disable();
    this.map.doubleClickZoom.disable();
    this.map.scrollWheelZoom.disable();
    this.map.boxZoom.disable();
    this.map.keyboard.disable();
    if (this.map.tap) this.map.tap.disable();

    // Add delay to ensure loading overlay is visible
    await new Promise(resolve => setTimeout(resolve, 500));

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
    } finally {
      // Re-enable map interaction after loading (success or failure)
      this.map.dragging.enable();
      this.map.touchZoom.enable();
      this.map.doubleClickZoom.enable();
      this.map.scrollWheelZoom.enable();
      this.map.boxZoom.enable();
      this.map.keyboard.enable();
      if (this.map.tap) this.map.tap.enable();

      // Hide loading overlay
      const loadingElement = document.getElementById('map-loading');
      if (loadingElement) {
        loadingElement.style.display = 'none';
        console.log('🚫 Loading overlay hidden - hexagons are fully loaded');
      }
    }
  }

  addStaticHexagonsToMap(geojsonData) {
    // Remove existing hexagon layer if it exists
    if (this.currentHexagonLayer) {
      this.map.removeLayer(this.currentHexagonLayer);
    }

    // Calculate max point count for color scaling
    const maxPoints = Math.max(...geojsonData.features.map(f => f.properties.point_count));

    const staticHexagonLayer = L.geoJSON(geojsonData, {
      style: (feature) => this.styleHexagon(),
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

    this.currentHexagonLayer = staticHexagonLayer;
    staticHexagonLayer.addTo(this.map);
  }

  styleHexagon() {
    return {
      fillColor: '#3388ff',
      fillOpacity: 0.3,
      color: '#3388ff',
      weight: 1,
      opacity: 0.3
    };
  }

  buildPopupContent(props) {
    const startDate = props.earliest_point ? new Date(props.earliest_point).toLocaleDateString() : 'N/A';
    const endDate = props.latest_point ? new Date(props.latest_point).toLocaleDateString() : 'N/A';
    const startTime = props.earliest_point ? new Date(props.earliest_point).toLocaleTimeString() : '';
    const endTime = props.latest_point ? new Date(props.latest_point).toLocaleTimeString() : '';

    return `
      <div style="font-size: 12px; line-height: 1.6; max-width: 300px;">
        <strong style="color: #3388ff;">📍 Location Data</strong><br>
        <div style="margin: 4px 0;">
          <strong>Points:</strong> ${props.point_count || 0}
        </div>
        ${props.h3_index ? `
        <div style="margin: 4px 0;">
          <strong>H3 Index:</strong><br>
          <code style="font-size: 10px; background: #f5f5f5; padding: 2px;">${props.h3_index}</code>
        </div>
        ` : ''}
        <div style="margin: 4px 0;">
          <strong>Time Range:</strong><br>
          <small>${startDate} ${startTime}<br>→ ${endDate} ${endTime}</small>
        </div>
        ${props.center ? `
        <div style="margin: 4px 0;">
          <strong>Center:</strong><br>
          <small>${props.center[0].toFixed(6)}, ${props.center[1].toFixed(6)}</small>
        </div>
        ` : ''}
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
}
