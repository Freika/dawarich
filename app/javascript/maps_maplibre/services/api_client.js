/**
 * API client for Maps V2
 * Wraps all API endpoints with consistent error handling
 */
export class ApiClient {
  constructor(apiKey) {
    this.apiKey = apiKey
    this.baseURL = "/api/v1"
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
      per_page: per_page.toString(),
      slim: "true",
      order: "asc",
    })

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points: ${response.statusText}`)
    }

    const points = await response.json()

    return {
      points,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
    }
  }

  /**
   * Fetch all points for date range (handles pagination with parallel requests)
   * @param {Object} options - { start_at, end_at, onProgress, onBatch, maxConcurrent }
   * @param {Function} options.onBatch - Called with accumulated points array after each batch
   * @returns {Promise<Array>} All points
   */
  async fetchAllPoints({
    start_at,
    end_at,
    onProgress = null,
    onBatch = null,
    maxConcurrent = 3,
  }) {
    // Report that fetching has started
    if (onProgress) {
      onProgress({
        loaded: 0,
        currentPage: 0,
        totalPages: 0,
        progress: 0,
      })
    }

    // First fetch to get total pages
    const firstPage = await this.fetchPoints({
      start_at,
      end_at,
      page: 1,
      per_page: 1000,
    })
    const totalPages = firstPage.totalPages

    // If only one page, return immediately
    if (totalPages === 1) {
      if (onProgress) {
        onProgress({
          loaded: firstPage.points.length,
          currentPage: 1,
          totalPages: 1,
          progress: 1.0,
        })
      }
      if (onBatch) {
        onBatch(firstPage.points)
      }
      return firstPage.points
    }

    // Initialize results array with first page
    const pageResults = [{ page: 1, points: firstPage.points }]
    let completedPages = 1

    // Report first page completed
    if (onProgress) {
      onProgress({
        loaded: firstPage.points.length,
        currentPage: 1,
        totalPages,
        progress: 1 / totalPages,
      })
    }
    if (onBatch) {
      onBatch(firstPage.points)
    }

    // Create array of remaining page numbers
    const remainingPages = Array.from(
      { length: totalPages - 1 },
      (_, i) => i + 2,
    )

    // Process pages in batches of maxConcurrent
    for (let i = 0; i < remainingPages.length; i += maxConcurrent) {
      const batch = remainingPages.slice(i, i + maxConcurrent)

      // Fetch batch in parallel
      const batchPromises = batch.map((page) =>
        this.fetchPoints({ start_at, end_at, page, per_page: 1000 }).then(
          (result) => ({ page, points: result.points }),
        ),
      )

      const batchResults = await Promise.all(batchPromises)
      pageResults.push(...batchResults)
      completedPages += batchResults.length

      // Call progress callback after each batch
      if (onProgress) {
        const progress = totalPages > 0 ? completedPages / totalPages : 1.0
        onProgress({
          loaded: pageResults.reduce((sum, r) => sum + r.points.length, 0),
          currentPage: completedPages,
          totalPages,
          progress,
        })
      }

      // Call batch callback with all accumulated points so far (sorted)
      if (onBatch) {
        const sorted = [...pageResults].sort((a, b) => a.page - b.page)
        onBatch(sorted.flatMap((r) => r.points))
      }
    }

    // Sort by page number to ensure correct order
    pageResults.sort((a, b) => a.page - b.page)

    // Flatten into single array
    return pageResults.flatMap((r) => r.points)
  }

  /**
   * Fetch visits for date range (paginated)
   * @param {Object} options - { start_at, end_at, page, per_page }
   * @returns {Promise<Object>} { visits, currentPage, totalPages }
   */
  async fetchVisitsPage({ start_at, end_at, page = 1, per_page = 500 }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      page: page.toString(),
      per_page: per_page.toString(),
    })

    const response = await fetch(`${this.baseURL}/visits?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch visits: ${response.statusText}`)
    }

    const visits = await response.json()

    return {
      visits,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
    }
  }

  /**
   * Fetch all visits for date range (handles pagination)
   * @param {Object} options - { start_at, end_at, onProgress }
   * @returns {Promise<Array>} All visits
   */
  async fetchVisits({ start_at, end_at, onProgress = null }) {
    const allVisits = []
    let page = 1
    let totalPages = 1

    do {
      const {
        visits,
        currentPage,
        totalPages: total,
      } = await this.fetchVisitsPage({ start_at, end_at, page, per_page: 500 })

      allVisits.push(...visits)
      totalPages = total
      page++

      if (onProgress) {
        const progress = totalPages > 0 ? currentPage / totalPages : 1.0
        onProgress({
          loaded: allVisits.length,
          currentPage,
          totalPages,
          progress,
        })
      }
    } while (page <= totalPages)

    return allVisits
  }

  /**
   * Fetch places (paginated)
   * @param {Object} options - { tag_ids, page, per_page }
   * @returns {Promise<Object>} { places, currentPage, totalPages }
   */
  async fetchPlacesPage({ tag_ids = [], page = 1, per_page = 500 } = {}) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: per_page.toString(),
    })

    if (tag_ids && tag_ids.length > 0) {
      for (const id of tag_ids) {
        params.append("tag_ids[]", id)
      }
    }

    const url = `${this.baseURL}/places?${params.toString()}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch places: ${response.statusText}`)
    }

    const places = await response.json()

    return {
      places,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
    }
  }

  /**
   * Fetch all places optionally filtered by tags (handles pagination)
   * @param {Object} options - { tag_ids, onProgress }
   * @returns {Promise<Array>} All places
   */
  async fetchPlaces({ tag_ids = [], onProgress = null } = {}) {
    const allPlaces = []
    let page = 1
    let totalPages = 1

    do {
      const {
        places,
        currentPage,
        totalPages: total,
      } = await this.fetchPlacesPage({ tag_ids, page, per_page: 500 })

      allPlaces.push(...places)
      totalPages = total
      page++

      if (onProgress) {
        const progress = totalPages > 0 ? currentPage / totalPages : 1.0
        onProgress({
          loaded: allPlaces.length,
          currentPage,
          totalPages,
          progress,
        })
      }
    } while (page <= totalPages)

    return allPlaces
  }

  /**
   * Fetch photos for date range
   */
  async fetchPhotos({ start_at, end_at }) {
    // Photos API uses start_date/end_date parameters
    // Pass dates as-is (matching V1 behavior)
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at,
    })

    const url = `${this.baseURL}/photos?${params}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

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
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch areas: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch single area by ID
   * @param {number} areaId - Area ID
   */
  async fetchArea(areaId) {
    const response = await fetch(`${this.baseURL}/areas/${areaId}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch tracks for a single page
   * @param {Object} options - { start_at, end_at, page, per_page }
   * @returns {Promise<Object>} { features, currentPage, totalPages, totalCount }
   */
  async fetchTracksPage({ start_at, end_at, page = 1, per_page = 500 }) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: per_page.toString(),
    })

    if (start_at) params.append("start_at", start_at)
    if (end_at) params.append("end_at", end_at)

    const url = `${this.baseURL}/tracks?${params.toString()}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch tracks: ${response.statusText}`)
    }

    const geojson = await response.json()

    return {
      features: geojson.features,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
      totalCount: parseInt(response.headers.get("X-Total-Count") || "0", 10),
    }
  }

  /**
   * Fetch all tracks (handles pagination with parallel requests)
   * @param {Object} options - { start_at, end_at, onProgress, maxConcurrent }
   * @returns {Promise<Object>} GeoJSON FeatureCollection
   */
  async fetchTracks({
    start_at,
    end_at,
    onProgress,
    onBatch = null,
    maxConcurrent = 3,
  } = {}) {
    // First fetch to get total pages
    const firstPage = await this.fetchTracksPage({
      start_at,
      end_at,
      page: 1,
      per_page: 500,
    })
    const totalPages = firstPage.totalPages

    // If only one page, return immediately
    if (totalPages === 1) {
      if (onProgress) {
        onProgress(1, 1)
      }
      if (onBatch) {
        onBatch(firstPage.features.length)
      }
      return {
        type: "FeatureCollection",
        features: firstPage.features,
      }
    }

    // Initialize results array with first page
    const pageResults = [{ page: 1, features: firstPage.features }]
    let completedPages = 1

    if (onBatch) {
      onBatch(firstPage.features.length)
    }

    // Create array of remaining page numbers
    const remainingPages = Array.from(
      { length: totalPages - 1 },
      (_, i) => i + 2,
    )

    // Process pages in batches of maxConcurrent
    for (let i = 0; i < remainingPages.length; i += maxConcurrent) {
      const batch = remainingPages.slice(i, i + maxConcurrent)

      // Fetch batch in parallel
      const batchPromises = batch.map((page) =>
        this.fetchTracksPage({ start_at, end_at, page, per_page: 500 }).then(
          (result) => ({ page, features: result.features }),
        ),
      )

      const batchResults = await Promise.all(batchPromises)
      pageResults.push(...batchResults)
      completedPages += batchResults.length

      // Call progress callback after each batch
      if (onProgress) {
        onProgress(completedPages, totalPages)
      }
      if (onBatch) {
        const totalFeatures = pageResults.reduce(
          (sum, r) => sum + r.features.length,
          0,
        )
        onBatch(totalFeatures)
      }
    }

    // Sort by page number to ensure correct order
    pageResults.sort((a, b) => a.page - b.page)

    // Flatten into single array
    return {
      type: "FeatureCollection",
      features: pageResults.flatMap((r) => r.features),
    }
  }

  /**
   * Fetch a single track with its segments (for lazy-loading on click)
   * @param {number|string} trackId - The track ID
   * @returns {Promise<Object>} GeoJSON Feature with segments
   */
  async fetchTrackWithSegments(trackId) {
    const url = `${this.baseURL}/tracks/${trackId}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch track: ${response.statusText}`)
    }

    const geojson = await response.json()

    // Return the first (and only) feature from the FeatureCollection
    return geojson.features?.[0] || null
  }

  /**
   * Create area
   * @param {Object} area - Area data
   */
  async createArea(area) {
    const response = await fetch(`${this.baseURL}/areas`, {
      method: "POST",
      headers: this.getHeaders(),
      body: JSON.stringify({ area }),
    })

    if (!response.ok) {
      throw new Error(`Failed to create area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Delete area by ID
   * @param {number} areaId - Area ID
   */
  async deleteArea(areaId) {
    const response = await fetch(`${this.baseURL}/areas/${areaId}`, {
      method: "DELETE",
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to delete area: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch points within a geographic area
   * @param {Object} options - { start_at, end_at, min_longitude, max_longitude, min_latitude, max_latitude }
   * @returns {Promise<Array>} Points within the area
   */
  async fetchPointsInArea({
    start_at,
    end_at,
    min_longitude,
    max_longitude,
    min_latitude,
    max_latitude,
  }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      min_longitude: min_longitude.toString(),
      max_longitude: max_longitude.toString(),
      min_latitude: min_latitude.toString(),
      max_latitude: max_latitude.toString(),
      per_page: "10000", // Get all points in area (up to 10k)
    })

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders(),
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
  async fetchVisitsInArea({
    start_at,
    end_at,
    sw_lat,
    sw_lng,
    ne_lat,
    ne_lng,
  }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      selection: "true",
      sw_lat: sw_lat.toString(),
      sw_lng: sw_lng.toString(),
      ne_lat: ne_lat.toString(),
      ne_lng: ne_lng.toString(),
    })

    const response = await fetch(`${this.baseURL}/visits?${params}`, {
      headers: this.getHeaders(),
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
      method: "DELETE",
      headers: this.getHeaders(),
      body: JSON.stringify({ point_ids: pointIds }),
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
      method: "PATCH",
      headers: this.getHeaders(),
      body: JSON.stringify({ visit: { status } }),
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
      method: "POST",
      headers: this.getHeaders(),
      body: JSON.stringify({ visit_ids: visitIds }),
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
      method: "POST",
      headers: this.getHeaders(),
      body: JSON.stringify({ visit_ids: visitIds, status }),
    })

    if (!response.ok) {
      throw new Error(`Failed to bulk update visits: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch a single page of points belonging to a specific track
   * @param {number} trackId - Track ID
   * @param {Object} options - { page, per_page }
   * @returns {Promise<Object>} { points, currentPage, totalPages }
   */
  async fetchTrackPointsPage(trackId, { page = 1, per_page = 1000 } = {}) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: per_page.toString(),
    })

    const response = await fetch(
      `${this.baseURL}/tracks/${trackId}/points?${params}`,
      { headers: this.getHeaders() },
    )

    if (!response.ok) {
      throw new Error(`Failed to fetch track points: ${response.statusText}`)
    }

    const points = await response.json()

    return {
      points,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
    }
  }

  /**
   * Fetch all points belonging to a specific track (handles pagination)
   * @param {number} trackId - Track ID
   * @param {Object} options - { per_page, maxConcurrent }
   * @returns {Promise<Array>} All points belonging to the track
   */
  async fetchTrackPoints(trackId, { per_page = 1000, maxConcurrent = 3 } = {}) {
    const firstPage = await this.fetchTrackPointsPage(trackId, {
      page: 1,
      per_page,
    })
    const totalPages = firstPage.totalPages

    if (totalPages <= 1) {
      return firstPage.points
    }

    const pageResults = [{ page: 1, points: firstPage.points }]

    const remainingPages = Array.from(
      { length: totalPages - 1 },
      (_, i) => i + 2,
    )

    for (let i = 0; i < remainingPages.length; i += maxConcurrent) {
      const batch = remainingPages.slice(i, i + maxConcurrent)
      const batchResults = await Promise.all(
        batch.map((page) =>
          this.fetchTrackPointsPage(trackId, { page, per_page }).then(
            (result) => ({ page, points: result.points }),
          ),
        ),
      )
      pageResults.push(...batchResults)
    }

    pageResults.sort((a, b) => a.page - b.page)
    return pageResults.flatMap((r) => r.points)
  }

  /**
   * Fetch timeline day feed for date range
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} { days: [...] }
   */
  async fetchTimeline({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })

    const response = await fetch(`${this.baseURL}/timeline?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch timeline: ${response.statusText}`)
    }

    return response.json()
  }

  getHeaders() {
    return {
      Authorization: `Bearer ${this.apiKey}`,
      "Content-Type": "application/json",
    }
  }
}
