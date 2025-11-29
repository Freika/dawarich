/**
 * API client for Maps V2
 * Wraps all API endpoints with consistent error handling
 */
export class ApiClient {
  constructor(apiKey) {
    this.apiKey = apiKey
    this.baseURL = '/api/v1'
  }

  /**
   * Fetch points for date range (paginated)
   * @param {Object} options - { start_at, end_at, page, per_page }
   * @returns {Promise<Object>} { points, currentPage, totalPages }
   */
  async fetchPoints({ start_at, end_at, page = 1, per_page = 1000 }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      page: page.toString(),
      per_page: per_page.toString()
    })

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points: ${response.statusText}`)
    }

    const points = await response.json()

    return {
      points,
      currentPage: parseInt(response.headers.get('X-Current-Page') || '1'),
      totalPages: parseInt(response.headers.get('X-Total-Pages') || '1')
    }
  }

  /**
   * Fetch all points for date range (handles pagination)
   * @param {Object} options - { start_at, end_at, onProgress }
   * @returns {Promise<Array>} All points
   */
  async fetchAllPoints({ start_at, end_at, onProgress = null }) {
    const allPoints = []
    let page = 1
    let totalPages = 1

    do {
      const { points, currentPage, totalPages: total } =
        await this.fetchPoints({ start_at, end_at, page, per_page: 1000 })

      allPoints.push(...points)
      totalPages = total
      page++

      if (onProgress) {
        // Avoid division by zero - if no pages, progress is 100%
        const progress = totalPages > 0 ? currentPage / totalPages : 1.0
        onProgress({
          loaded: allPoints.length,
          currentPage,
          totalPages,
          progress
        })
      }
    } while (page <= totalPages)

    return allPoints
  }

  /**
   * Fetch visits for date range
   */
  async fetchVisits({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })

    const response = await fetch(`${this.baseURL}/visits?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch visits: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch places optionally filtered by tags
   */
  async fetchPlaces({ tag_ids = [] } = {}) {
    const params = new URLSearchParams()

    if (tag_ids && tag_ids.length > 0) {
      tag_ids.forEach(id => params.append('tag_ids[]', id))
    }

    const url = `${this.baseURL}/places${params.toString() ? '?' + params.toString() : ''}`

    const response = await fetch(url, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch places: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch photos for date range
   */
  async fetchPhotos({ start_at, end_at }) {
    // Photos API uses start_date/end_date parameters
    // Pass dates as-is (matching V1 behavior)
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at
    })

    const url = `${this.baseURL}/photos?${params}`
    console.log('[ApiClient] Fetching photos from:', url)
    console.log('[ApiClient] With headers:', this.getHeaders())

    const response = await fetch(url, {
      headers: this.getHeaders()
    })

    console.log('[ApiClient] Photos response status:', response.status)

    if (!response.ok) {
      throw new Error(`Failed to fetch photos: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch areas
   */
  async fetchAreas() {
    const response = await fetch(`${this.baseURL}/areas`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch areas: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch tracks
   */
  async fetchTracks() {
    const response = await fetch(`${this.baseURL}/tracks`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch tracks: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Create area
   * @param {Object} area - Area data
   */
  async createArea(area) {
    const response = await fetch(`${this.baseURL}/areas`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ area })
    })

    if (!response.ok) {
      throw new Error(`Failed to create area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch points within a geographic area
   * @param {Object} options - { start_at, end_at, min_longitude, max_longitude, min_latitude, max_latitude }
   * @returns {Promise<Array>} Points within the area
   */
  async fetchPointsInArea({ start_at, end_at, min_longitude, max_longitude, min_latitude, max_latitude }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      min_longitude: min_longitude.toString(),
      max_longitude: max_longitude.toString(),
      min_latitude: min_latitude.toString(),
      max_latitude: max_latitude.toString(),
      per_page: '10000' // Get all points in area (up to 10k)
    })

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points in area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch visits within a geographic area
   * @param {Object} options - { start_at, end_at, sw_lat, sw_lng, ne_lat, ne_lng }
   * @returns {Promise<Array>} Visits within the area
   */
  async fetchVisitsInArea({ start_at, end_at, sw_lat, sw_lng, ne_lat, ne_lng }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      selection: 'true',
      sw_lat: sw_lat.toString(),
      sw_lng: sw_lng.toString(),
      ne_lat: ne_lat.toString(),
      ne_lng: ne_lng.toString()
    })

    const response = await fetch(`${this.baseURL}/visits?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch visits in area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Bulk delete points
   * @param {Array<number>} pointIds - Array of point IDs to delete
   * @returns {Promise<Object>} { message, count }
   */
  async bulkDeletePoints(pointIds) {
    const response = await fetch(`${this.baseURL}/points/bulk_destroy`, {
      method: 'DELETE',
      headers: this.getHeaders(),
      body: JSON.stringify({ point_ids: pointIds })
    })

    if (!response.ok) {
      throw new Error(`Failed to delete points: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Update visit status (confirm/decline)
   * @param {number} visitId - Visit ID
   * @param {string} status - 'confirmed' or 'declined'
   * @returns {Promise<Object>} Updated visit
   */
  async updateVisitStatus(visitId, status) {
    const response = await fetch(`${this.baseURL}/visits/${visitId}`, {
      method: 'PATCH',
      headers: this.getHeaders(),
      body: JSON.stringify({ visit: { status } })
    })

    if (!response.ok) {
      throw new Error(`Failed to update visit status: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Merge multiple visits
   * @param {Array<number>} visitIds - Array of visit IDs to merge
   * @returns {Promise<Object>} Merged visit
   */
  async mergeVisits(visitIds) {
    const response = await fetch(`${this.baseURL}/visits/merge`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ visit_ids: visitIds })
    })

    if (!response.ok) {
      throw new Error(`Failed to merge visits: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Bulk update visit status
   * @param {Array<number>} visitIds - Array of visit IDs to update
   * @param {string} status - 'confirmed' or 'declined'
   * @returns {Promise<Object>} Update result
   */
  async bulkUpdateVisits(visitIds, status) {
    const response = await fetch(`${this.baseURL}/visits/bulk_update`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ visit_ids: visitIds, status })
    })

    if (!response.ok) {
      throw new Error(`Failed to bulk update visits: ${response.statusText}`)
    }

    return response.json()
  }

  getHeaders() {
    return {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json'
    }
  }
}
