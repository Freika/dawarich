export function flightWindows(flights) {
  const features = Array.isArray(flights) ? flights : flights?.features || []

  return features
    .map((feature) => {
      const props = feature.properties || {}
      const dep = props.departure_time
      const arr = props.arrival_time
      if (!dep || !arr) return null

      const start = Date.parse(dep) / 1000
      const end = Date.parse(arr) / 1000
      if (Number.isNaN(start) || Number.isNaN(end)) return null

      return [Math.min(start, end), Math.max(start, end)]
    })
    .filter(Boolean)
}

function inAnyWindow(timestamp, windows) {
  return windows.some(([start, end]) => timestamp >= start && timestamp <= end)
}

export function maskPoints(featureCollection, windows) {
  if (!windows || windows.length === 0 || !featureCollection) {
    return featureCollection
  }

  return {
    ...featureCollection,
    features: (featureCollection.features || []).filter((feature) => {
      const timestamp = feature.properties?.timestamp
      return timestamp == null || !inAnyWindow(timestamp, windows)
    }),
  }
}

function toUnixSeconds(value) {
  if (value == null) return null
  if (typeof value === "number") return value
  const parsed = Date.parse(value) / 1000
  return Number.isNaN(parsed) ? null : parsed
}

function lineSpan(feature) {
  const props = feature.properties || {}
  const start =
    props.startTime ??
    props.start_timestamp ??
    props.startTimestamp ??
    toUnixSeconds(props.start_at)
  const end =
    props.endTime ??
    props.end_timestamp ??
    props.endTimestamp ??
    toUnixSeconds(props.end_at)
  return [start, end]
}

export function maskLines(featureCollection, windows) {
  if (!windows || windows.length === 0 || !featureCollection) {
    return featureCollection
  }

  return {
    ...featureCollection,
    features: (featureCollection.features || []).filter((feature) => {
      const [start, end] = lineSpan(feature)
      if (start == null || end == null) return true

      const fullyContained = windows.some(
        ([windowStart, windowEnd]) => start >= windowStart && end <= windowEnd,
      )
      return !fullyContained
    }),
  }
}
