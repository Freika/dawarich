/**
 * Pure math utilities for the video export preview animation.
 * Ported from video-service/src/lib/interpolate.ts, route-stats.ts, camera.ts.
 */

const R = 6371 // Earth radius in km

function toRad(deg) {
  return (deg * Math.PI) / 180
}

function toDeg(rad) {
  return (rad * 180) / Math.PI
}

export function haversineDistance(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

export function interpolatePosition(coords, progress) {
  if (coords.length === 0) return { lon: 0, lat: 0, timestamp: 0 }
  if (coords.length === 1 || progress <= 0) return coords[0]
  if (progress >= 1) return coords[coords.length - 1]

  const totalSegments = coords.length - 1
  const exactIndex = progress * totalSegments
  const idx = Math.floor(exactIndex)
  const fraction = exactIndex - idx

  const from = coords[idx]
  const to = coords[Math.min(idx + 1, totalSegments)]

  return {
    lon: from.lon + (to.lon - from.lon) * fraction,
    lat: from.lat + (to.lat - from.lat) * fraction,
    timestamp: from.timestamp + (to.timestamp - from.timestamp) * fraction,
  }
}

export function getRouteUpToProgress(coords, progress) {
  if (coords.length === 0) return []
  if (coords.length === 1) return [[coords[0].lon, coords[0].lat]]

  const totalSegments = coords.length - 1
  const exactIndex = progress * totalSegments
  const floorIdx = Math.floor(exactIndex)
  const fraction = exactIndex - floorIdx

  const result = coords.slice(0, floorIdx + 1).map((c) => [c.lon, c.lat])

  if (fraction > 0 && floorIdx < totalSegments) {
    const from = coords[floorIdx]
    const to = coords[floorIdx + 1]
    result.push([
      from.lon + (to.lon - from.lon) * fraction,
      from.lat + (to.lat - from.lat) * fraction,
    ])
  }

  return result
}

export function cumulativeDistance(coords, progress) {
  if (coords.length < 2 || progress <= 0) return 0

  const totalSegments = coords.length - 1
  const exactIndex = progress * totalSegments
  const endIdx = Math.floor(exactIndex)

  let distance = 0
  for (let i = 0; i < endIdx && i < totalSegments; i++) {
    distance += haversineDistance(
      coords[i].lat,
      coords[i].lon,
      coords[i + 1].lat,
      coords[i + 1].lon,
    )
  }

  if (endIdx < totalSegments) {
    const fraction = exactIndex - endIdx
    const segmentDist = haversineDistance(
      coords[endIdx].lat,
      coords[endIdx].lon,
      coords[endIdx + 1].lat,
      coords[endIdx + 1].lon,
    )
    distance += segmentDist * fraction
  }

  return distance
}

export function estimateSpeed(coords, progress) {
  if (coords.length < 2) return 0

  const totalSegments = coords.length - 1
  const exactIndex = progress * totalSegments
  const idx = Math.min(Math.floor(exactIndex), totalSegments - 1)
  const nextIdx = Math.min(idx + 1, totalSegments)

  const curr = coords[idx]
  const next = coords[nextIdx]
  if (!curr || !next || curr.timestamp === next.timestamp) return 0

  const dist = haversineDistance(curr.lat, curr.lon, next.lat, next.lon)
  const timeDiff = (next.timestamp - curr.timestamp) / 3600
  return timeDiff > 0 ? dist / timeDiff : 0
}

export function computeBearing(from, to) {
  const dLon = toRad(to.lon - from.lon)
  const lat1Rad = toRad(from.lat)
  const lat2Rad = toRad(to.lat)

  const y = Math.sin(dLon) * Math.cos(lat2Rad)
  const x =
    Math.cos(lat1Rad) * Math.sin(lat2Rad) -
    Math.sin(lat1Rad) * Math.cos(lat2Rad) * Math.cos(dLon)

  return (toDeg(Math.atan2(y, x)) + 360) % 360
}
