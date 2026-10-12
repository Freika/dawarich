/**
 * Great-circle interpolation for flight geometries. The flights API delivers
 * each flight as a 2-point LineString; these helpers replace it with a smooth
 * arc so long-haul flights follow the spherical shortest path.
 */

const toRad = (deg) => (deg * Math.PI) / 180
const toDeg = (rad) => (rad * 180) / Math.PI

/**
 * Interpolate a great-circle path between two [lon, lat] coordinates.
 * Longitudes are unwrapped so antimeridian-crossing arcs render as one line.
 * @param {[number, number]} start
 * @param {[number, number]} end
 * @returns {Array<[number, number]>}
 */
export function greatCircleCoordinates(start, end) {
  const [lon1, lat1] = start
  const [lon2, lat2] = end
  const phi1 = toRad(lat1)
  const lambda1 = toRad(lon1)
  const phi2 = toRad(lat2)
  const lambda2 = toRad(lon2)

  const delta =
    2 *
    Math.asin(
      Math.sqrt(
        Math.sin((phi2 - phi1) / 2) ** 2 +
          Math.cos(phi1) *
            Math.cos(phi2) *
            Math.sin((lambda2 - lambda1) / 2) ** 2,
      ),
    )

  if (delta < 1e-9 || Math.abs(Math.sin(delta)) < 1e-9) {
    return [start, end]
  }

  const steps = Math.min(128, Math.max(16, Math.round(toDeg(delta) * 2)))
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

  for (let i = 1; i < coords.length; i++) {
    while (coords[i][0] - coords[i - 1][0] > 180) coords[i][0] -= 360
    while (coords[i][0] - coords[i - 1][0] < -180) coords[i][0] += 360
  }

  return coords
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
