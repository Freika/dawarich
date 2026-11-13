import { dateRange, fetchPagesInOrder, maskPrivacyZones } from "./helpers"

/** Visit and Place reads and writes. Mixed into ApiClient; `this` is the client. */
export const visitsPlacesApi = {
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
  },

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
  },

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
  },

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
  },

  /**
   * Merge multiple visits
   * @param {Array<number>} visitIds - Array of visit IDs to merge
   * @returns {Promise<Object>} Merged visit
   */
  mergeVisits(visitIds) {
    return this._send("POST", "/visits/merge", "Failed to merge visits", {
      visit_ids: visitIds,
    })
  },

  /**
   * Delete a single visit
   * @param {number} visitId - Visit ID to delete
   * @returns {Promise<Object>} Deleted visit payload
   */
  deleteVisit(visitId) {
    return this._send("DELETE", `/visits/${visitId}`, "Failed to delete visit")
  },

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
  },

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
  },

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
  },

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
  },
}
