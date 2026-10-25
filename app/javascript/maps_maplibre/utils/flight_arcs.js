/**
 * Great-circle interpolation for flight geometries. The flights API delivers
 * each flight as a 2-point LineString; these helpers replace it with a smooth
 * arc so long-haul flights follow the spherical shortest path.
 */

const MERCATOR_MAX_LATITUDE = 85.0511287798
const toRad = (deg) => (deg * Math.PI) / 180
const toDeg = (rad) => (rad * 180) / Math.PI

function angularDistance([lon1, lat1], [lon2, lat2]) {
  const phi1 = toRad(lat1)
  const phi2 = toRad(lat2)
  return (
    2 *
    Math.asin(
      Math.sqrt(
        Math.sin((phi2 - phi1) / 2) ** 2 +
          Math.cos(phi1) *
            Math.cos(phi2) *
            Math.sin(toRad(lon2 - lon1) / 2) ** 2,
      ),
    )
  )
}

function slerp([lon1, lat1], [lon2, lat2], delta, steps) {
  const phi1 = toRad(lat1)
  const lambda1 = toRad(lon1)
  const phi2 = toRad(lat2)
  const lambda2 = toRad(lon2)
  const coords = []

  for (let i = 0; i <= steps; i++) {
    const f = i / steps
    const a = Math.sin((1 - f) * delta) / Math.sin(delta)
    const b = Math.sin(f * delta) / Math.sin(delta)
    const x =
      a * Math.cos(phi1) * Math.cos(lambda1) +
      b * Math.cos(phi2) * Math.cos(lambda2)
    const y =
      a * Math.cos(phi1) * Math.sin(lambda1) +
      b * Math.cos(phi2) * Math.sin(lambda2)
    const z = a * Math.sin(phi1) + b * Math.sin(phi2)
    coords.push([
      toDeg(Math.atan2(y, x)),
      toDeg(Math.atan2(z, Math.sqrt(x * x + y * y))),
    ])
  }

  return coords
}

/**
 * Interpolate a great-circle path between two [lon, lat] coordinates.
 * Longitudes are unwrapped so antimeridian-crossing arcs render as one line.
 * @param {[number, number]} start
 * @param {[number, number]} end
 * @returns {Array<[number, number]>}
 */
export function greatCircleCoordinates(start, end) {
  const delta = angularDistance(start, end)

  if (delta < 1e-9 || Math.abs(Math.sin(delta)) < 1e-9) {
    return [start, end]
  }

  const steps = Math.min(128, Math.max(16, Math.round(toDeg(delta) * 2)))
  const coords = slerp(start, end, delta, steps)

  for (let i = 1; i < coords.length; i++) {
    while (coords[i][0] - coords[i - 1][0] > 180) coords[i][0] -= 360
    while (coords[i][0] - coords[i - 1][0] < -180) coords[i][0] += 360
  }

  return coords
}

/**
 * Insert great-circle points into gaps wider than maxStepDegrees of arc.
 * Longitudes stay within ±180, so callers keep their antimeridian handling.
 * @param {Array<[number, number]>} coordinates
 * @param {number} maxStepDegrees
 * @returns {Array<[number, number]>}
 */
export function densifyGreatCircle(coordinates, maxStepDegrees = 1) {
  const maxStep = toRad(maxStepDegrees)
  const result = coordinates.slice(0, 1)

  for (let i = 1; i < coordinates.length; i++) {
    const start = coordinates[i - 1]
    const end = coordinates[i]
    const delta = angularDistance(start, end)

    if (delta > maxStep && Math.abs(Math.sin(delta)) > 1e-9) {
      const steps = Math.ceil(delta / maxStep)
      result.push(...slerp(start, end, delta, steps).slice(1, -1))
    }
    result.push(end)
  }

  return result
}

/**
 * Densify along great circles and break the line where it leaves the Web
 * Mercator world, so polar stretches exit and re-enter like vector tiles do
 * instead of tracing the map's top edge.
 * @param {Array<[number, number]>} coordinates
 * @returns {Array<Array<[number, number]>>}
 */
export function greatCircleLines(coordinates) {
  const lines = [[]]
  for (const coord of densifyGreatCircle(coordinates)) {
    if (Math.abs(coord[1]) > MERCATOR_MAX_LATITUDE) {
      if (lines.at(-1).length) lines.push([])
    } else {
      lines.at(-1).push(coord)
    }
  }
  return lines.filter((line) => line.length)
}

/**
 * Replace each flight's 2-point LineString with a great-circle arc.
 * Features with missing or degenerate geometry pass through untouched.
 * @param {Object} featureCollection
 * @returns {Object}
 */
export function arcifyFlights(featureCollection) {
  if (!featureCollection?.features) return featureCollection

  return {
    ...featureCollection,
    features: featureCollection.features.map((feature) => {
      const coords = feature.geometry?.coordinates
      if (
        feature.geometry?.type !== "LineString" ||
        !Array.isArray(coords) ||
        coords.length !== 2 ||
        coords.some(
          (c) => !Array.isArray(c) || c.some((v) => typeof v !== "number"),
        )
      ) {
        return feature
      }

      return {
        ...feature,
        geometry: {
          ...feature.geometry,
          coordinates: greatCircleCoordinates(coords[0], coords[1]),
        },
      }
    }),
  }
}
