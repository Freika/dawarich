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
