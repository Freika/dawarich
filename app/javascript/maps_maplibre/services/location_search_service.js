/**
 * Location Search Service
 * Handles API calls for location search (suggestions and visits)
 */

export class LocationSearchService {
  constructor(apiKey) {
    this.apiKey = apiKey
    this.baseHeaders = {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json'
    }
  }

  /**
   * Fetch location suggestions based on query
   * @param {string} query - Search query
   * @returns {Promise<Array>} Array of location suggestions
   */
  async fetchSuggestions(query) {
    if (!query || query.length < 2) {
      return []
    }

    try {
      const response = await fetch(
        `/api/v1/locations/suggestions?q=${encodeURIComponent(query)}`,
        {
          method: 'GET',
          headers: this.baseHeaders
        }
      )

      if (!response.ok) {
        throw new Error(`Suggestions API error: ${response.status}`)
      }

      const data = await response.json()

      // Transform suggestions to expected format
      // API returns coordinates as [lat, lon], we need { lat, lon }
      const suggestions = (data.suggestions || []).map(suggestion => ({
        name: suggestion.name,
        address: suggestion.address,
        lat: suggestion.coordinates?.[0],
        lon: suggestion.coordinates?.[1],
        type: suggestion.type
      }))

      return suggestions
    } catch (error) {
      console.error('LocationSearchService: Suggestion fetch error:', error)
      throw error
    }
  }

  /**
   * Search for visits at a specific location
   * @param {Object} params - Search parameters
   * @param {number} params.lat - Latitude
   * @param {number} params.lon - Longitude
   * @param {string} params.name - Location name
   * @param {string} params.address - Location address
   * @returns {Promise<Object>} Search results with locations and visits
   */
  async searchVisits({ lat, lon, name, address = '' }) {
    try {
      const params = new URLSearchParams({
        lat: lat.toString(),
        lon: lon.toString(),
        name,
        address
      })

      const response = await fetch(`/api/v1/locations?${params}`, {
        method: 'GET',
        headers: this.baseHeaders
      })

      if (!response.ok) {
        throw new Error(`Location search API error: ${response.status}`)
      }

      const data = await response.json()
      return data
    } catch (error) {
      console.error('LocationSearchService: Visit search error:', error)
      throw error
    }
  }

  /**
   * Create a new visit
   * @param {Object} visitData - Visit data
   * @returns {Promise<Object>} Created visit
   */
  async createVisit(visitData) {
    try {
      const response = await fetch('/api/v1/visits', {
        method: 'POST',
        headers: this.baseHeaders,
        body: JSON.stringify({ visit: visitData })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || data.message || 'Failed to create visit')
      }

      return data
    } catch (error) {
      console.error('LocationSearchService: Create visit error:', error)
      throw error
    }
  }
}
