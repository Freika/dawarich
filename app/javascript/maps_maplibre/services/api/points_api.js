import { dateRange, fetchRemainingPages, maskPrivacyZones } from "./helpers"

/** Point reads and writes. Mixed into ApiClient; `this` is the client. */
export const pointsApi = {
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
  },

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
  },

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
  },

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
  },

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
  },

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
  },

  /**
   * Delete a single point
   * @param {number} pointId - Point ID to delete
   * @returns {Promise<Object>} Deleted point payload
   */
  deletePoint(pointId) {
    return this._send("DELETE", `/points/${pointId}`, "Failed to delete point")
  },

  /** Clear a point's anomaly flag and keep the filter from setting it again. */
  markPointValid(pointId) {
    return this._send(
      "PATCH",
      `/points/${pointId}/mark_valid`,
      "Failed to mark point as correct",
    )
  },

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
  },

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
  },
}
