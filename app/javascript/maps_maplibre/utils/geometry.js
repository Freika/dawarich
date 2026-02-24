/**
 * Calculate distance between two points in meters
 * @param {Array} point1 - [lng, lat]
 * @param {Array} point2 - [lng, lat]
 * @returns {number} Distance in meters
 */
export function calculateDistance(point1, point2) {
  const [lng1, lat1] = point1
  const [lng2, lat2] = point2

  const R = 6371000 // Earth radius in meters
  const φ1 = (lat1 * Math.PI) / 180
  const φ2 = (lat2 * Math.PI) / 180
  const Δφ = ((lat2 - lat1) * Math.PI) / 180
  const Δλ = ((lng2 - lng1) * Math.PI) / 180

  const a =
    Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2)

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

  return R * c
}

/**
 * Create circle polygon
 * @param {Array} center - [lng, lat]
 * @param {number} radiusInMeters
 * @param {number} points - Number of points in polygon
 * @returns {Array} Coordinates array
 */
export function createCircle(center, radiusInMeters, points = 64) {
  const [lng, lat] = center
  const coords = []

  const distanceX = radiusInMeters / (111320 * Math.cos((lat * Math.PI) / 180))
  const distanceY = radiusInMeters / 110540

  for (let i = 0; i < points; i++) {
    const theta = (i / points) * (2 * Math.PI)
    const x = distanceX * Math.cos(theta)
    const y = distanceY * Math.sin(theta)
    coords.push([lng + x, lat + y])
  }

  coords.push(coords[0]) // Close the circle

  return coords
}

/**
 * Create rectangle from bounds
 * @param {Object} bounds - { minLng, minLat, maxLng, maxLat }
 * @returns {Array} Coordinates array
 */
export function createRectangle(bounds) {
  const { minLng, minLat, maxLng, maxLat } = bounds

  return [
    [
      [minLng, minLat],
      [maxLng, minLat],
      [maxLng, maxLat],
      [minLng, maxLat],
      [minLng, minLat],
    ],
  ]
}
