import { BaseLayer } from './base_layer'

/**
 * Scratch map layer
 * Highlights countries that have been visited based on points' country_name attribute
 * Extracts country names from points (via database country relationship)
 * Matches country names to polygons in lib/assets/countries.geojson by name field
 * "Scratches off" visited countries by overlaying gold/amber polygons
 */
export class ScratchLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'scratch', ...options })
    this.visitedCountries = new Set()
    this.countriesData = null
    this.loadingCountries = null // Promise for loading countries
    this.apiClient = options.apiClient // For authenticated requests
  }

  async add(data) {
    const points = data.features || []

    // Load country boundaries
    await this.loadCountryBoundaries()

    // Detect which countries have been visited
    this.visitedCountries = this.detectCountriesFromPoints(points)

    // Create GeoJSON with visited countries
    const geojson = this.createCountriesGeoJSON()

    super.add(geojson)
  }

  async update(data) {
    const points = data.features || []

    // Countries already loaded from add()
    this.visitedCountries = this.detectCountriesFromPoints(points)

    const geojson = this.createCountriesGeoJSON()

    super.update(geojson)
  }

  /**
   * Extract country names from points' country_name attribute
   * Points already have country association from database (country_id relationship)
   * @param {Array} points - Array of point features with properties.country_name
   * @returns {Set} Set of country names
   */
  detectCountriesFromPoints(points) {
    const visitedCountries = new Set()

    // Extract unique country names from points
    points.forEach(point => {
      const countryName = point.properties?.country_name

      if (countryName && countryName !== 'Unknown') {
        visitedCountries.add(countryName)
      }
    })

    return visitedCountries
  }

  /**
   * Load country boundaries from internal API endpoint
   * Endpoint: GET /api/v1/countries/borders
   */
  async loadCountryBoundaries() {
    // Return existing promise if already loading
    if (this.loadingCountries) {
      return this.loadingCountries
    }

    // Return immediately if already loaded
    if (this.countriesData) {
      return
    }

    this.loadingCountries = (async () => {
      try {
        // Use internal API endpoint with authentication
        const headers = {}
        if (this.apiClient) {
          headers['Authorization'] = `Bearer ${this.apiClient.apiKey}`
        }

        const response = await fetch('/api/v1/countries/borders.json', {
          headers: headers
        })

        if (!response.ok) {
          throw new Error(`Failed to load country borders: ${response.statusText}`)
        }

        this.countriesData = await response.json()
      } catch (error) {
        console.error('[ScratchLayer] Failed to load country boundaries:', error)
        // Fallback to empty data
        this.countriesData = { type: 'FeatureCollection', features: [] }
      }
    })()

    return this.loadingCountries
  }

  /**
   * Create GeoJSON for visited countries
   * Matches visited country names from points to boundary polygons by name
   * @returns {Object} GeoJSON FeatureCollection
   */
  createCountriesGeoJSON() {
    if (!this.countriesData || this.visitedCountries.size === 0) {
      return {
        type: 'FeatureCollection',
        features: []
      }
    }

    // Filter country features by matching name field to visited country names
    const visitedFeatures = this.countriesData.features.filter(country => {
      const countryName = country.properties.name || country.properties.NAME

      if (!countryName) return false

      // Case-insensitive exact match
      return Array.from(this.visitedCountries).some(visitedName =>
        countryName.toLowerCase() === visitedName.toLowerCase()
      )
    })

    return {
      type: 'FeatureCollection',
      features: visitedFeatures
    }
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      // Country fill
      {
        id: this.id,
        type: 'fill',
        source: this.sourceId,
        paint: {
          'fill-color': '#fbbf24', // Amber/gold color
          'fill-opacity': 0.3
        }
      },
      // Country outline
      {
        id: `${this.id}-outline`,
        type: 'line',
        source: this.sourceId,
        paint: {
          'line-color': '#f59e0b',
          'line-width': 1,
          'line-opacity': 0.6
        }
      }
    ]
  }

  getLayerIds() {
    return [this.id, `${this.id}-outline`]
  }
}
