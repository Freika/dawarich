import L from "leaflet";

export class ScratchLayer {
  constructor(map, markers, countryCodesMap, apiKey) {
    this.map = map;
    this.markers = markers;
    this.countryCodesMap = countryCodesMap;
    this.apiKey = apiKey;
    this.scratchLayer = null;
    this.worldBordersData = null;
  }

  async setup() {
    this.scratchLayer = L.geoJSON(null, {
      style: {
        fillColor: '#FFD700',
        fillOpacity: 0.3,
        color: '#FFA500',
        weight: 1
      }
    });

    try {
      // Up-to-date version can be found on Github:
      // https://raw.githubusercontent.com/datasets/geo-countries/master/data/countries.geojson
      const worldData = await this._fetchWorldBordersData();

      const visitedCountries = this.getVisitedCountries();
      console.log('Current visited countries:', visitedCountries);

      if (visitedCountries.length === 0) {
        console.log('No visited countries found');
        return this.scratchLayer;
      }

      const filteredFeatures = worldData.features.filter(feature =>
        visitedCountries.includes(feature.properties["ISO3166-1-Alpha-2"])
      );

      console.log('Filtered features for visited countries:', filteredFeatures.length);

      this.scratchLayer.addData({
        type: 'FeatureCollection',
        features: filteredFeatures
      });
    } catch (error) {
      console.error('Error loading GeoJSON:', error);
    }

    return this.scratchLayer;
  }

  async _fetchWorldBordersData() {
    if (this.worldBordersData) {
      return this.worldBordersData;
    }

    console.log('Loading world borders data');
    const response = await fetch('/api/v1/countries/borders.json', {
      headers: {
        'Accept': 'application/geo+json,application/json',
        'Authorization': `Bearer ${this.apiKey}`
      }
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    this.worldBordersData = await response.json();
    return this.worldBordersData;
  }

  getVisitedCountries() {
    if (!this.markers) return [];

    return [...new Set(
      this.markers
        .filter(marker => marker[7]) // Ensure country exists
        .map(marker => {
          // Convert country name to ISO code, or return the original if not found
          return this.countryCodesMap[marker[7]] || marker[7];
        })
    )];
  }

  toggle() {
    if (!this.scratchLayer) {
      console.warn('Scratch layer not initialized');
      return;
    }

    if (this.map.hasLayer(this.scratchLayer)) {
      this.map.removeLayer(this.scratchLayer);
    } else {
      this.scratchLayer.addTo(this.map);
    }
  }

  async refresh() {
    console.log('Refreshing scratch layer with current data');

    if (!this.scratchLayer) {
      console.log('Scratch layer not initialized, setting up');
      await this.setup();
      return;
    }

    try {
      // Clear existing data
      this.scratchLayer.clearLayers();

      // Get current visited countries based on current markers
      const visitedCountries = this.getVisitedCountries();
      console.log('Current visited countries:', visitedCountries);

      if (visitedCountries.length === 0) {
        console.log('No visited countries found');
        return;
      }

      // Fetch country borders data (reuse if already loaded)
      const worldData = await this._fetchWorldBordersData();

      // Filter for visited countries
      const filteredFeatures = worldData.features.filter(feature =>
        visitedCountries.includes(feature.properties["ISO3166-1-Alpha-2"])
      );

      console.log('Filtered features for visited countries:', filteredFeatures.length);

      // Add the filtered country data to the scratch layer
      this.scratchLayer.addData({
        type: 'FeatureCollection',
        features: filteredFeatures
      });

    } catch (error) {
      console.error('Error refreshing scratch layer:', error);
    }
  }

  // Update markers reference when they change
  updateMarkers(markers) {
    this.markers = markers;
  }

  // Get the Leaflet layer for use in layer controls
  getLayer() {
    return this.scratchLayer;
  }

  // Check if layer is currently visible on map
  isVisible() {
    return this.scratchLayer && this.map.hasLayer(this.scratchLayer);
  }

  // Remove layer from map
  remove() {
    if (this.scratchLayer && this.map.hasLayer(this.scratchLayer)) {
      this.map.removeLayer(this.scratchLayer);
    }
  }

  // Add layer to map
  addToMap() {
    if (this.scratchLayer) {
      this.scratchLayer.addTo(this.map);
    }
  }
}
