const EPOCH_SECONDS_LIMIT = 1e10

/**
 * Normalize a broadcast timestamp (epoch seconds, epoch milliseconds, or an
 * ISO string) into epoch milliseconds. Returns null for empty/unparseable input.
 */
export function parseTimestamp(value) {
  if (value === null || value === undefined || value === "") {
    return null
  }

  const numeric = Number(value)
  if (Number.isFinite(numeric)) {
    return numeric < EPOCH_SECONDS_LIMIT ? numeric * 1000 : numeric
  }

  const parsed = Date.parse(value)
  return Number.isNaN(parsed) ? null : parsed
}

/**
 * Decide whether a realtime point falls inside the map's active date range.
 * `range.treatEndAsOpen` skips the upper bound so the default "today" window
 * keeps showing points recorded after local midnight.
 */
export function pointMatchesActiveDateRange(timestamp, range = {}) {
  const pointTime = parseTimestamp(timestamp)
  if (pointTime === null) {
    return false
  }

  const startTime = parseTimestamp(range.startValue)
  if (startTime !== null && pointTime < startTime) {
    return false
  }

  if (range.treatEndAsOpen) {
    return true
  }

  const endTime = parseTimestamp(range.endValue)
  if (endTime !== null && pointTime > endTime) {
    return false
  }

  return true
}
