import { fetchRemainingPages, maskPrivacyZones } from "./helpers"

/** Track reads. Mixed into ApiClient; `this` is the client. */
export const tracksApi = {
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

    maskPrivacyZones(params)
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
  },

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
    onTotalKnown = null,
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

    // Surface the server-reported total as soon as page 1 lands. Lets the
    // loading badge show "N tracks" while the remaining pages and rendering
    // catch up, so users get a count up-front instead of seeing 0 → 342.
    if (onTotalKnown) {
      onTotalKnown(firstPage.totalCount || firstPage.features.length)
    }

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

    onBatch?.(firstPage.features.length)

    const features = await fetchRemainingPages({
      firstItems: firstPage.features,
      totalPages,
      maxConcurrent,
      fetchItems: (page) =>
        this.fetchTracksPage({ start_at, end_at, page, per_page: 500 }).then(
          (result) => result.features,
        ),
      onBatchDone: (completedPages, loadedItems) => {
        onProgress?.(completedPages, totalPages)
        onBatch?.(loadedItems().length)
      },
    })

    return { type: "FeatureCollection", features }
  },

  /**
   * Fetch a single track with its segments (for lazy-loading on click)
   * @param {number|string} trackId - The track ID
   * @returns {Promise<Object>} GeoJSON Feature with segments
   */
  async fetchTrackWithSegments(
    trackId,
    { signal, startAt, endAt, unmasked = false } = {},
  ) {
    const params = new URLSearchParams()
    if (!unmasked) maskPrivacyZones(params)
    if (this.importId) params.set("import_id", this.importId)
    if (startAt && endAt) {
      params.set("start_at", startAt)
      params.set("end_at", endAt)
    }
    const suffix = params.size ? `?${params}` : ""
    const url = `${this.baseURL}/tracks/${trackId}${suffix}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
      signal,
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch track: ${response.statusText}`)
    }

    const geojson = await response.json()

    // Return the first (and only) feature from the FeatureCollection
    return geojson.features?.[0] || null
  },

  /**
   * Fetch a single page of points belonging to a specific track
   * @param {number} trackId - Track ID
   * @param {Object} options - { page, per_page }
   * @returns {Promise<Object>} { points, currentPage, totalPages }
   */
  async fetchTrackPointsPage(
    trackId,
    { page = 1, per_page = 1000, unmasked = false } = {},
  ) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: per_page.toString(),
    })
    if (this.importId) params.set("import_id", this.importId)
    if (!unmasked) maskPrivacyZones(params)

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
  },

  /**
   * Fetch all points belonging to a specific track (handles pagination)
   * @param {number} trackId - Track ID
   * @param {Object} options - { per_page, maxConcurrent }
   * @returns {Promise<Array>} All points belonging to the track
   */
  async fetchTrackPoints(
    trackId,
    { per_page = 1000, maxConcurrent = 3, unmasked = false } = {},
  ) {
    const firstPage = await this.fetchTrackPointsPage(trackId, {
      page: 1,
      per_page,
      unmasked,
    })
    const totalPages = firstPage.totalPages

    if (totalPages <= 1) {
      return firstPage.points
    }

    return fetchRemainingPages({
      firstItems: firstPage.points,
      totalPages,
      maxConcurrent,
      fetchItems: (page) =>
        this.fetchTrackPointsPage(trackId, { page, per_page, unmasked }).then(
          (result) => result.points,
        ),
    })
  },
}
