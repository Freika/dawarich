/** Shared pieces of the Maps V2 API client. */
export const PRIVACY_FLAG = "mask_privacy_zones"

export function maskPrivacyZones(params) {
  params.set(PRIVACY_FLAG, "true")
}

export function dateRange(start_at, end_at) {
  return start_at && end_at ? { start_at, end_at } : {}
}

/**
 * Fetches pages 2..totalPages, maxConcurrent at a time.
 * @returns {Promise<Array>} Every item, in page order
 */
export async function fetchRemainingPages({
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
export async function fetchPagesInOrder(fetchPage, onProgress) {
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
