import { BaseLayer } from './base_layer'

/**
 * Scratch map layer
 * Highlights countries that have been visited based on points' country_name attribute
 * "Scratches off" countries by overlaying gold/yellow polygons
 */
export class ScratchLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'scratch', ...options })
    this.visitedCountries = new Set()
    this.countriesData = null
    this.loadingCountries = null // Promise for loading countries
  }

  async add(data) {
    // Extract visited countries from points
    const points = data.features || []
    this.visitedCountries = this.detectCountries(points)

    // Load country boundaries if not already loaded
    await this.loadCountryBoundaries()

    // Create GeoJSON with visited countries
    const geojson = this.createCountriesGeoJSON()

    super.add(geojson)
  }

  async update(data) {
    const points = data.features || []
    this.visitedCountries = this.detectCountries(points)

    // Countries already loaded from add()
    const geojson = this.createCountriesGeoJSON()
    super.update(geojson)
  }

  /**
   * Detect which countries have been visited from points' country_name attribute
   * @param {Array} points - Array of point features
   * @returns {Set} Set of country names
   */
  detectCountries(points) {
    const countries = new Set()

    points.forEach(point => {
      const countryName = point.properties?.country_name
      if (countryName && countryName.trim()) {
        // Normalize country name
        countries.add(countryName.trim())
      }
    })

    console.log(`Scratch map: Found ${countries.size} visited countries`, Array.from(countries))
    return countries
  }

  /**
   * Load country boundaries from Natural Earth data via CDN
   * Uses simplified 110m resolution for performance
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
        // Load Natural Earth 110m countries data (simplified)
        const response = await fetch(
          'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson'
        )

        if (!response.ok) {
          throw new Error(`Failed to load countries: ${response.statusText}`)
        }

        this.countriesData = await response.json()
        console.log(`Scratch map: Loaded ${this.countriesData.features.length} country boundaries`)
      } catch (error) {
        console.error('Failed to load country boundaries:', error)
        // Fallback to empty data
        this.countriesData = { type: 'FeatureCollection', features: [] }
      }
    })()

    return this.loadingCountries
  }

  /**
   * Create GeoJSON for visited countries
   * Matches visited country names to boundary polygons
   * @returns {Object} GeoJSON FeatureCollection
   */
  createCountriesGeoJSON() {
    if (!this.countriesData || this.visitedCountries.size === 0) {
      return {
        type: 'FeatureCollection',
        features: []
      }
    }

    // Filter countries by visited names
    const visitedFeatures = this.countriesData.features.filter(country => {
      // Try multiple name fields for matching
      const name = country.properties?.NAME ||
                   country.properties?.name ||
                   country.properties?.ADMIN ||
                   country.properties?.admin

      if (!name) return false

      // Check if this country was visited (case-insensitive match)
      return this.visitedCountries.has(name) ||
             Array.from(this.visitedCountries).some(visited =>
               visited.toLowerCase() === name.toLowerCase()
             )
    })

    console.log(`Scratch map: Highlighting ${visitedFeatures.length} countries`)

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
