export const RouteSegmenter = {
  haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371
    const dLat = ((lat2 - lat1) * Math.PI) / 180
    const dLon = ((lon2 - lon1) * Math.PI) / 180
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return R * c
  },
  getInterpolatedLat(lat1, lon1, lat2, lon2, interpLon) {
    const nLat1 = Number(lat1)
    const nLon1 = Number(lon1)
    const nLat2 = Number(lat2)
    const nLon2 = Number(lon2)
    const nInterpLon = Number(interpLon)
    if ([nLat1, nLon1, nLat2, nLon2, nInterpLon].some(Number.isNaN)) {
      return null
    }
    if (Math.abs(nLon1 - nLon2) < 0.0000001) {
      return nLat1
    }
    const toRad = (deg) => (deg * Math.PI) / 180
    const toDeg = (rad) => (rad * 180) / Math.PI
    const φ1 = toRad(nLat1)
    const λ1 = toRad(nLon1)
    const φ2 = toRad(nLat2)
    const λ2 = toRad(nLon2)
    const λ3 = toRad(nInterpLon)
    const sinDeltaL = Math.sin(λ2 - λ1)
    const term1 = Math.tan(φ1) * Math.sin(λ2 - λ3)
    const term2 = Math.tan(φ2) * Math.sin(λ3 - λ1)
    const tanPhi = (term1 + term2) / sinDeltaL
    const result = toDeg(Math.atan(tanPhi))
    return Number.isFinite(result) ? result : null
  },
  findIDLCrossings(coords) {
    const crossings = [0]
    for (let i = 0; i < coords.length - 1; i++) {
      const currentLng = parseFloat(coords[i].longitude)
      const nextLng = parseFloat(coords[i + 1].longitude)
      if (Number.isNaN(currentLng) || Number.isNaN(nextLng)) continue
      if (Math.abs(currentLng - nextLng) > 180) {
        crossings.push(i + 1)
      }
    }
    crossings.push(coords.length)
    return crossings
  },
  unwrapCoordinates(segment) {
    const crossingIndices = RouteSegmenter.findIDLCrossings(segment)
    const coordsList = []
    for (let i = 0; i < crossingIndices.length - 1; i++) {
      const subsegment = segment.slice(
        crossingIndices[i],
        crossingIndices[i + 1],
      )
      const coords = subsegment.map((p) => [
        parseFloat(p.longitude),
        parseFloat(p.latitude),
      ])
      coordsList.push(coords)
    }
    if (coordsList.length > 1) {
      for (let i = 0; i < coordsList.length - 1; i++) {
        const lastPoint = coordsList[i].at(-1)
        const nextPoint = coordsList[i + 1][0]
        const interpLat = RouteSegmenter.getInterpolatedLat(
          lastPoint[1],
          lastPoint[0],
          nextPoint[1],
          nextPoint[0],
          180,
        )
        const safeInterpLat = Number.isFinite(interpLat)
          ? interpLat
          : lastPoint[1]
        coordsList[i].push([180 * Math.sign(lastPoint[0]), safeInterpLat])
        coordsList[i + 1].unshift([
          180 * Math.sign(nextPoint[0]),
          safeInterpLat,
        ])
      }
    }
    return coordsList
  },
  calculateSegmentDistance(segment) {
    let totalDistance = 0
    for (let i = 0; i < segment.length - 1; i++) {
      totalDistance += RouteSegmenter.haversineDistance(
        segment[i].latitude,
        segment[i].longitude,
        segment[i + 1].latitude,
        segment[i + 1].longitude,
      )
    }
    return totalDistance
  },
  splitIntoSegments(points, options) {
    const { distanceThresholdKm, timeThresholdMinutes } = options
    const segments = []
    let currentSegment = [points[0]]
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1]
      const curr = points[i]
      const distance = RouteSegmenter.haversineDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      )
      const timeDiff = (curr.timestamp - prev.timestamp) / 60
      if (distance > distanceThresholdKm || timeDiff > timeThresholdMinutes) {
        if (currentSegment.length > 1) {
          segments.push(currentSegment)
        }
        currentSegment = [curr]
      } else {
        currentSegment.push(curr)
      }
    }
    if (currentSegment.length > 1) {
      segments.push(currentSegment)
    }
    return segments
  },
  segmentToFeature(segment) {
    const coordinates = RouteSegmenter.unwrapCoordinates(segment)
    const totalDistance = RouteSegmenter.calculateSegmentDistance(segment)
    const startTime = segment[0].timestamp
    const endTime = segment[segment.length - 1].timestamp
    const routeId = `route-${startTime}-${endTime}`
    const isMultiPath = coordinates.length > 1
    return {
      type: "Feature",
      geometry: {
        type: isMultiPath ? "MultiLineString" : "LineString",
        coordinates: isMultiPath ? coordinates : coordinates[0],
      },
      properties: {
        id: routeId,
        pointCount: isMultiPath ? coordinates.flat().length : segment.length,
        startTime,
        endTime,
        distance: totalDistance,
      },
    }
  },
  pointsToRoutes(points, options = {}) {
    if (points.length < 2) {
      return { type: "FeatureCollection", features: [] }
    }
    const distanceThresholdKm = options.distanceThresholdMeters || 500
    const timeThresholdMinutes = options.timeThresholdMinutes || 60
    const buckets = points.reduce((acc, p) => {
      const key = p.tracker_id || ""
      if (!acc[key]) acc[key] = []
      acc[key].push(p)
      return acc
    }, {})
    const features = Object.values(buckets).flatMap((bucket) => {
      if (bucket.length < 2) return []
      const sorted = bucket.slice().sort((a, b) => a.timestamp - b.timestamp)
      const segments = RouteSegmenter.splitIntoSegments(sorted, {
        distanceThresholdKm,
        timeThresholdMinutes,
      })
      return segments.map((segment) => RouteSegmenter.segmentToFeature(segment))
    })
    return {
      type: "FeatureCollection",
      features,
    }
  },
}
