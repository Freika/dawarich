export function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

export function pointFeature(point, trackId) {
  const properties = { ...point, id: Number(point.id), kind: "point" }
  if (trackId != null) properties.track_id = Number(trackId)

  return {
    type: "Feature",
    geometry: {
      type: "Point",
      coordinates: [Number(point.longitude), Number(point.latitude)],
    },
    properties,
  }
}

export function segmentFeature(segment) {
  return {
    type: "Feature",
    geometry: { type: "LineString", coordinates: segment.coordinates || [] },
    properties: { ...segment, id: Number(segment.id), kind: "segment" },
  }
}

export function uncoveredTrackFeature(points, segments) {
  if (points.length < 2 || segments.length === 0) return null

  const coverage = new Uint8Array(points.length - 1)
  const timestamps = points.map((point) => Number(point.properties.timestamp))
  const orderedTimestamps = points.every(
    (point, index) =>
      point.properties.timestamp != null &&
      Number.isFinite(timestamps[index]) &&
      (index === 0 || timestamps[index] >= timestamps[index - 1]),
  )
  const lowerBound = (value) => {
    let low = 0
    let high = timestamps.length
    while (low < high) {
      const middle = (low + high) >> 1
      if (timestamps[middle] < value) low = middle + 1
      else high = middle
    }
    return low
  }
  const upperBound = (value) => {
    let low = 0
    let high = timestamps.length
    while (low < high) {
      const middle = (low + high) >> 1
      if (timestamps[middle] <= value) low = middle + 1
      else high = middle
    }
    return low
  }

  for (const segment of segments) {
    if (segment.geometry.coordinates.length < 2) continue
    const { start_index: startIndex, end_index: endIndex } = segment.properties
    if (startIndex != null && endIndex != null) {
      const first = Number(startIndex)
      const last = Number(endIndex)
      if (Number.isInteger(first) && Number.isInteger(last))
        coverage.fill(1, Math.max(0, first), Math.max(0, last))
      continue
    }
    if (!orderedTimestamps) continue
    const { start_time: startTime, end_time: endTime } = segment.properties
    if (startTime == null || endTime == null) continue
    const start = Number(startTime)
    const end = Number(endTime)
    if (!Number.isFinite(start) || !Number.isFinite(end)) continue
    coverage.fill(1, lowerBound(start), Math.max(0, upperBound(end) - 1))
  }

  const runs = []
  let run = null
  for (let index = 0; index < points.length - 1; index += 1) {
    if (coverage[index]) {
      run = null
      continue
    }
    if (!run) {
      run = [points[index].geometry.coordinates]
      runs.push(run)
    }
    run.push(points[index + 1].geometry.coordinates)
  }

  if (runs.length === 0) return null
  return {
    type: "Feature",
    geometry: { type: "MultiLineString", coordinates: runs },
    properties: { kind: "uncovered-track" },
  }
}

export function updateSegmentGeometry(points, segments) {
  for (const segment of segments) {
    const { start_index: startIndex, end_index: endIndex } = segment.properties
    let segmentPoints
    if (startIndex != null && endIndex != null) {
      segmentPoints = points.slice(Number(startIndex), Number(endIndex) + 1)
    } else {
      const start = Number(segment.properties.start_time)
      const end = Number(segment.properties.end_time)
      segmentPoints = points.filter((point) => {
        const timestamp = Number(point.properties.timestamp)
        return timestamp >= start && timestamp <= end
      })
    }
    segment.geometry.coordinates = segmentPoints.map(
      (point) => point.geometry.coordinates,
    )
  }
}

export function snapshotCoordinates(snapshot, pointId) {
  const feature = snapshot?.features.find(
    (candidate) =>
      candidate.properties.kind === "point" &&
      Number(candidate.properties.id) === Number(pointId),
  )
  if (!feature) return null
  const [longitude, latitude] = feature.geometry.coordinates
  return { longitude, latitude }
}
