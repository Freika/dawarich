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
   * Fetch photos for date range
   */
  async fetchPhotos({ start_at, end_at }) {
    // Photos API uses start_date/end_date parameters
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at
    })

    const response = await fetch(`${this.baseURL}/photos?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch photos: ${response.statusText}`)
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
