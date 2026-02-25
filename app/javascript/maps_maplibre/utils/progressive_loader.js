/**
 * Progressive loader for large datasets
 * Loads data in chunks with progress feedback and abort capability
 */
export class ProgressiveLoader {
  constructor(options = {}) {
    this.onProgress = options.onProgress || null
    this.onComplete = options.onComplete || null
    this.abortController = null
  }

  /**
   * Load data progressively
   * @param {Function} fetchFn - Function that fetches one page
   * @param {Object} options - { batchSize, maxConcurrent, maxPoints }
   * @returns {Promise<Array>}
   */
  async load(fetchFn, options = {}) {
    const {
      batchSize = 1000,
      maxConcurrent = 3,
      maxPoints = 100000, // Limit for safety
    } = options

    this.abortController = new AbortController()
    const allData = []
    let page = 1
    let totalPages = 1
    const activeRequests = []

    try {
      do {
        // Check abort
        if (this.abortController.signal.aborted) {
          throw new Error("Load cancelled")
        }

        // Check max points limit
        if (allData.length >= maxPoints) {
          console.warn(`Reached max points limit: ${maxPoints}`)
          break
        }

        // Limit concurrent requests
        while (activeRequests.length >= maxConcurrent) {
          await Promise.race(activeRequests)
        }

        const requestPromise = fetchFn({
          page,
          per_page: batchSize,
          signal: this.abortController.signal,
        }).then((result) => {
          allData.push(...result.data)

          if (result.totalPages) {
            totalPages = result.totalPages
          }

          this.onProgress?.({
            loaded: allData.length,
            total: Math.min(totalPages * batchSize, maxPoints),
            currentPage: page,
            totalPages,
            progress: page / totalPages,
          })

          // Remove from active
          const idx = activeRequests.indexOf(requestPromise)
          if (idx > -1) activeRequests.splice(idx, 1)

          return result
        })

        activeRequests.push(requestPromise)
        page++
      } while (page <= totalPages && allData.length < maxPoints)

      // Wait for remaining
      await Promise.all(activeRequests)

      this.onComplete?.(allData)
      return allData
    } catch (error) {
      if (error.name === "AbortError" || error.message === "Load cancelled") {
        console.log("Progressive load cancelled")
        return allData // Return partial data
      }
      throw error
    }
  }

  /**
   * Cancel loading
   */
  cancel() {
    this.abortController?.abort()
  }
}
