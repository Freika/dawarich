import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"

/**
 * API client for Maps V2
 * Wraps all API endpoints with consistent error handling
 */
const PRIVACY_FLAG = "mask_privacy_zones"

function maskPrivacyZones(params) {
  params.set(PRIVACY_FLAG, "true")
}

function dateRange(start_at, end_at) {
  return start_at && end_at ? { start_at, end_at } : {}
}

/**
 * Fetches pages 2..totalPages, maxConcurrent at a time.
 * @returns {Promise<Array>} Every item, in page order
 */
async function fetchRemainingPages({
  firstItems,
  totalPages,
  maxConcurrent,
  fetchItems,
  onBatchDone = null,
}) {
  const results = [{ page: 1, items: firstItems }]
  const itemsInPageOrder = () =>
    [...results].sort((a, b) => a.page - b.page).flatMap((r) => r.items)

  for (let start = 2; start <= totalPages; start += maxConcurrent) {
    const last = Math.min(start + maxConcurrent - 1, totalPages)
    const pages = Array.from({ length: last - start + 1 }, (_, i) => start + i)
    const batch = await Promise.all(
      pages.map((page) => fetchItems(page).then((items) => ({ page, items }))),
    )
    results.push(...batch)
    onBatchDone?.(results.length, itemsInPageOrder)
  }

  return itemsInPageOrder()
}

/** Fetches one page at a time until the server reports the last one. */
async function fetchPagesInOrder(fetchPage, onProgress) {
  const allItems = []
  let page = 1
  let totalPages = 1

  do {
    const result = await fetchPage(page)
    allItems.push(...result.items)
    totalPages = result.totalPages
    page++

    onProgress?.({
      loaded: allItems.length,
      currentPage: result.currentPage,
      totalPages,
      progress: totalPages > 0 ? result.currentPage / totalPages : 1.0,
    })
  } while (page <= totalPages)

  return allItems
}

export class ApiClient {
  constructor(apiKey, importId = null) {
    this.apiKey = apiKey
    this.baseURL = "/api/v1"
    this.importId = importId
  }

  /**
   * Fetch points for date range (paginated)
   * @param {Object} options - { start_at, end_at, page, per_page }
   * @returns {Promise<Object>} { points, currentPage, totalPages }
   */
  async fetchPoints({ start_at, end_at, page = 1, per_page = 1000, signal }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      page: page.toString(),
      per_page: per_page.toString(),
      slim: "true",
      order: "asc",
    })

    if (this.importId) params.append("import_id", this.importId)
    maskPrivacyZones(params)

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders(),
      signal,
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points: ${response.statusText}`)
    }

    const points = await response.json()

    return {
      points,
      currentPage: parseInt(response.headers.get("X-Current-Page") || "1", 10),
      totalPages: parseInt(response.headers.get("X-Total-Pages") || "1", 10),
      totalPointsInRange: parseInt(
        response.headers.get("X-Total-Points-In-Range") || "0",
        10,
      ),
      scopedPoints: parseInt(
        response.headers.get("X-Scoped-Points") || "0",
        10,
      ),
    }
  }

  /**
   * Fetch all-history H3 openings; the date range only highlights first discoveries
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} { h3_indexes, metadata }
   */
  async fetchFogHexagons({ start_at, end_at, snapshot_id }) {
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at,
    })
    if (snapshot_id) params.set("snapshot_id", snapshot_id)
    maskPrivacyZones(params)

    const response = await fetch(
      `${this.baseURL}/maps/hexagons/fog?${params}`,
      {
        headers: this.getHeaders(),
      },
    )

    if (!response.ok) {
      throw new Error(`Failed to fetch fog hexagons: ${response.statusText}`)
    }

    return response.json()
  }

  async fetchRangeStatistics({ start_at, end_at, signal }) {
    const params = new URLSearchParams({ start_at, end_at })
    maskPrivacyZones(params)
    if (this.importId) params.set("import_id", this.importId)
    const response = await fetch(`${this.baseURL}/maps/statistics?${params}`, {
      headers: this.getHeaders(),
      signal,
    })
    if (!response.ok)
      throw new Error(`Failed to fetch statistics: ${response.status}`)
    return response.json()
  }

  /** Fetch a bounded extent for tile-backed Point and Track history. */
  async fetchHistoryBounds({ start_at, end_at }) {
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at,
      robust: "true",
    })
    if (this.importId) params.set("import_id", this.importId)
    maskPrivacyZones(params)

    const response = await fetch(
      `${this.baseURL}/maps/hexagons/bounds?${params}`,
      { headers: this.getHeaders() },
    )
    if (response.status === 404) return null
    if (!response.ok) {
      throw new Error(`Failed to fetch history bounds: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch all points for date range (handles pagination with parallel requests)
   * @param {Object} options - { start_at, end_at, onProgress, onBatch, maxConcurrent }
   * @param {Function} options.onBatch - Called with accumulated points array after each batch
   * @returns {Promise<{points: Array, totalPointsInRange: number}>}
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
    const totalPointsInRange = firstPage.totalPointsInRange

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
      return { points: firstPage.points, totalPointsInRange }
    }

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

    const points = await fetchRemainingPages({
      firstItems: firstPage.points,
      totalPages,
      maxConcurrent,
      fetchItems: (page) =>
        this.fetchPoints({ start_at, end_at, page, per_page: 1000 }).then(
          (result) => result.points,
        ),
      onBatchDone: (completedPages, loadedItems) => {
        onProgress?.({
          loaded: loadedItems().length,
          currentPage: completedPages,
          totalPages,
          progress: totalPages > 0 ? completedPages / totalPages : 1.0,
        })
        onBatch?.(loadedItems())
      },
    })

    return { points, totalPointsInRange }
  }

  /**
   * Fetch visits for date range (paginated). Optional bounds narrow the
   * query to visits whose place falls inside the rectangle — backed by
   * Visits::FindWithinBoundingBox via `selection=true`.
   * @param {Object} options - { start_at, end_at, page, per_page, sw_lat, sw_lng, ne_lat, ne_lng }
   * @returns {Promise<Object>} { visits, currentPage, totalPages }
   */
  async fetchVisitsPage({
    start_at,
    end_at,
    page = 1,
    per_page = 500,
    sw_lat,
    sw_lng,
    ne_lat,
    ne_lng,
  }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      page: page.toString(),
      per_page: per_page.toString(),
    })

    if (
      Number.isFinite(sw_lat) &&
      Number.isFinite(sw_lng) &&
      Number.isFinite(ne_lat) &&
      Number.isFinite(ne_lng)
    ) {
      params.set("selection", "true")
      params.set("sw_lat", sw_lat.toString())
      params.set("sw_lng", sw_lng.toString())
      params.set("ne_lat", ne_lat.toString())
      params.set("ne_lng", ne_lng.toString())
    }

    maskPrivacyZones(params)
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
   * Fetch visits for date range, optionally bounded to a viewport bbox.
   * Loops pages until the API reports no more. When bounds are provided
   * the result is windowed to that rectangle — fewer pages, smaller
   * payloads, and the layer no longer hauls every visit at world zoom.
   * @param {Object} options - { start_at, end_at, sw_lat, sw_lng, ne_lat, ne_lng, onProgress }
   * @returns {Promise<Array>} Visits in range (and viewport, if bounded)
   */
  async fetchVisits({
    start_at,
    end_at,
    sw_lat,
    sw_lng,
    ne_lat,
    ne_lng,
    onProgress = null,
  }) {
    return fetchPagesInOrder(
      (page) =>
        this.fetchVisitsPage({
          start_at,
          end_at,
          page,
          per_page: 500,
          sw_lat,
          sw_lng,
          ne_lat,
          ne_lng,
        }).then((result) => ({ ...result, items: result.visits })),
      onProgress,
    )
  }

  /**
   * Fetch places (paginated)
   * @param {Object} options - { tag_ids, page, per_page }
   * @returns {Promise<Object>} { places, currentPage, totalPages }
   */
  async fetchPlacesPage({
    tag_ids = [],
    page = 1,
    per_page = 500,
    filter,
  } = {}) {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: per_page.toString(),
    })

    if (tag_ids && tag_ids.length > 0) {
      for (const id of tag_ids) {
        params.append("tag_ids[]", id)
      }
    }

    maskPrivacyZones(params)
    if (filter) params.set("filter", filter)
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
  async fetchPlaces({
    tag_ids = [],
    onProgress = null,
    filter,
    includeArchived = false,
  } = {}) {
    if (includeArchived) {
      const [active, archived] = await Promise.all([
        this.fetchPlaces({ tag_ids, onProgress }),
        this.fetchPlaces({ tag_ids, filter: "archived" }),
      ])
      return [...active, ...archived]
    }

    return fetchPagesInOrder(
      (page) =>
        this.fetchPlacesPage({ tag_ids, page, per_page: 500, filter }).then(
          (result) => ({ ...result, items: result.places }),
        ),
      onProgress,
    )
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

    maskPrivacyZones(params)
    const url = `${this.baseURL}/photos?${params}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      Toast.error(translate("messages.failed_to_load_photos"))
      throw new Error(`Failed to fetch photos: ${response.statusText}`)
    }

    const failedSources = response.headers.get("X-Photo-Source-Errors")
    if (failedSources) {
      Toast.warning(
        translate("messages.some_photo_sources_unavailable", {
          sources: failedSources.split(",").join(", "),
        }),
      )
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
  }

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
  }

  /**
   * Fetch points within a geographic area
   * @param {Object} options - { start_at, end_at, min_longitude, max_longitude, min_latitude, max_latitude }
   * @returns {Promise<{points: Array, truncated: boolean}>} Points within the area; truncated when more exist than one page holds
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
      ...dateRange(start_at, end_at),
      min_longitude: min_longitude.toString(),
      max_longitude: max_longitude.toString(),
      min_latitude: min_latitude.toString(),
      max_latitude: max_latitude.toString(),
      include_anomalies: "true",
      per_page: "10000", // Get all points in area (up to 10k)
    })

    if (this.importId) params.append("import_id", this.importId)

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points in area: ${response.statusText}`)
    }

    return {
      points: await response.json(),
      truncated: Number(response.headers.get("X-Total-Pages")) > 1,
    }
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
      ...dateRange(start_at, end_at),
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
   * Delete a single point
   * @param {number} pointId - Point ID to delete
   * @returns {Promise<Object>} Deleted point payload
   */
  deletePoint(pointId) {
    return this._send("DELETE", `/points/${pointId}`, "Failed to delete point")
  }

  /** Clear a point's anomaly flag and keep the filter from setting it again. */
  markPointValid(pointId) {
    return this._send(
      "PATCH",
      `/points/${pointId}/mark_valid`,
      "Failed to mark point as correct",
    )
  }

  /**
   * Bulk delete points
   * @param {Array<number>} pointIds - Array of point IDs to delete
   * @returns {Promise<Object>} { message, count }
   * @throws {Error} with `body` property holding the parsed JSON error response when available
   */
  async bulkDeletePoints(pointIds) {
    const response = await fetch(`${this.baseURL}/points/bulk_destroy`, {
      method: "DELETE",
      headers: this.getHeaders(),
      body: JSON.stringify({ point_ids: pointIds }),
    })

    if (!response.ok) {
      let body = null
      try {
        body = await response.json()
      } catch (_) {
        // Non-JSON error body — leave body as null.
      }
      const error = new Error(
        body?.error || `Failed to delete points: ${response.statusText}`,
      )
      error.status = response.status
      error.body = body
      throw error
    }

    return response.json()
  }

  /**
   * Update visit status (confirm/decline)
   * @param {number} visitId - Visit ID
   * @param {string} status - 'confirmed' or 'declined'
   * @returns {Promise<Object>} Updated visit
   */
  updateVisitStatus(visitId, status) {
    return this._send(
      "PATCH",
      `/visits/${visitId}`,
      "Failed to update visit status",
      { visit: { status } },
    )
  }

  /**
   * Merge multiple visits
   * @param {Array<number>} visitIds - Array of visit IDs to merge
   * @returns {Promise<Object>} Merged visit
   */
  mergeVisits(visitIds) {
    return this._send("POST", "/visits/merge", "Failed to merge visits", {
      visit_ids: visitIds,
    })
  }

  /**
   * Delete a single visit
   * @param {number} visitId - Visit ID to delete
   * @returns {Promise<Object>} Deleted visit payload
   */
  deleteVisit(visitId) {
    return this._send("DELETE", `/visits/${visitId}`, "Failed to delete visit")
  }

  /**
   * Bulk delete visits
   * @param {Array<number>} visitIds - Array of visit IDs to delete
   * @returns {Promise<Object>} { message, count }
   */
  bulkDestroyVisits(visitIds) {
    return this._send(
      "DELETE",
      "/visits/bulk_destroy",
      "Failed to delete visits",
      { visit_ids: visitIds },
    )
  }

  /**
   * Bulk update visit status
   * @param {Array<number>} visitIds - Array of visit IDs to update
   * @param {string} status - 'confirmed' or 'declined'
   * @returns {Promise<Object>} Update result
   */
  bulkUpdateVisits(visitIds, status) {
    return this._send(
      "POST",
      "/visits/bulk_update",
      "Failed to bulk update visits",
      { visit_ids: visitIds, status },
    )
  }

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
  }

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
  }

  async movePointPosition(
    pointId,
    { latitude, longitude, pointRevision, trackRevision, historyScope },
  ) {
    const response = await fetch(`${this.baseURL}/points/${pointId}/position`, {
      method: "PATCH",
      headers: this.getHeaders(),
      body: JSON.stringify({
        point: {
          latitude: String(latitude),
          longitude: String(longitude),
          revision: pointRevision,
        },
        track_revision: trackRevision,
        history_scope: {
          start_at: historyScope.startAt,
          end_at: historyScope.endAt,
          import_id: this.importId,
        },
      }),
    })
    const payload = await response.json()

    if (!response.ok) {
      const error = new Error(
        payload?.error?.message || `Point move failed (${response.status})`,
      )
      error.status = response.status
      error.payload = payload
      throw error
    }

    return payload
  }

  async fetchVisitedCountries({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })
    if (this.importId) params.set("import_id", this.importId)

    const response = await fetch(
      `${this.baseURL}/countries/visited?${params}`,
      {
        headers: this.getHeaders(),
      },
    )
    if (!response.ok) {
      throw new Error(
        `Failed to fetch visited countries: ${response.statusText}`,
      )
    }

    return response.json()
  }

  /**
   * Fetch timeline day feed for date range
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} { days: [...] }
   */
  async fetchTimeline({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })
    maskPrivacyZones(params)

    const response = await fetch(`${this.baseURL}/timeline?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch timeline: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch AirTrail flights for a date range as a GeoJSON FeatureCollection.
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} GeoJSON FeatureCollection
   */
  async fetchFlights({ start_at, end_at } = {}) {
    const params = new URLSearchParams()
    if (start_at) params.set("start_at", start_at)
    if (end_at) params.set("end_at", end_at)
    maskPrivacyZones(params)

    const response = await fetch(`${this.baseURL}/flights?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch flights: ${response.statusText}`)
    }

    return response.json()
  }

  async fetchPrivacyZones() {
    try {
      const response = await fetch(`${this.baseURL}/tags/privacy_zones`, {
        headers: this.getHeaders(),
      })
      if (!response.ok) return { zones: [], fingerprint: null, failed: true }

      const fingerprint = response.headers.get("X-Privacy-Zones-Fingerprint")
      const zones = (await response.json()).flatMap((zone) =>
        (zone.places || []).map(({ masked_area: area }) => ({
          lon: Number(area.longitude),
          lat: Number(area.latitude),
          radiusMeters: Number(area.radius_meters),
        })),
      )
      return { zones, fingerprint: fingerprint || null }
    } catch {
      return { zones: [], fingerprint: null, failed: true }
    }
  }

  /** Send a write and return its JSON; a failed response throws `failure`. */
  async _send(method, path, failure, body = undefined) {
    const response = await fetch(`${this.baseURL}${path}`, {
      method,
      headers: this.getHeaders(),
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })

    if (!response.ok) {
      throw new Error(`${failure}: ${response.statusText}`)
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
