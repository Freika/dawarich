export function calculateDistance(point1, point2) {
  const [lng1, lat1] = point1
  const [lng2, lat2] = point2

  const R = 6371000
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

  coords.push(coords[0])

  return coords
}

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

const OUTLIER_MIN_COORDS = 50
const OUTLIER_BUDGET_RATIO = 0.01
const OUTLIER_MIN_BUDGET = 5
const OUTLIER_GAP_RATIO = 0.2
const OUTLIER_MIN_GAP_DEGREES = 1

export function trimOutlierCoords(coords) {
  if (coords.length < OUTLIER_MIN_COORDS) return coords

  const [lonLo, lonHi] = axisInlierRange(coords.map((c) => c[0]))
  const [latLo, latHi] = axisInlierRange(coords.map((c) => c[1]))

  const inliers = coords.filter(
    ([lon, lat]) =>
      lon >= lonLo && lon <= lonHi && lat >= latLo && lat <= latHi,
  )
  return inliers.length ? inliers : coords
}

function axisInlierRange(values) {
  const sorted = [...values].sort((a, b) => a - b)
  const n = sorted.length
  const span = sorted[n - 1] - sorted[0]
  const gapThreshold = Math.max(
    span * OUTLIER_GAP_RATIO,
    OUTLIER_MIN_GAP_DEGREES,
  )
  const budget = Math.max(
    OUTLIER_MIN_BUDGET,
    Math.floor(n * OUTLIER_BUDGET_RATIO),
  )

  let lo = 0
  for (let i = 1; i <= budget; i++) {
    if (sorted[i] - sorted[i - 1] > gapThreshold) lo = i
  }

  let hi = n - 1
  for (let i = n - 2; i >= n - 1 - budget; i--) {
    if (sorted[i + 1] - sorted[i] > gapThreshold) hi = i
  }

  return [sorted[lo], sorted[hi]]
}
