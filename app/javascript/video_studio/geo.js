// Great-circle distance in metres. Same maths as
// maps_maplibre/utils/geometry.js#calculateDistance, kept here with a scalar
// signature so every video_studio module stays import-free of the map stack —
// that is what lets the pure modules run under `node --test`.
const EARTH_RADIUS_M = 6371000

export function haversineDistance(lat1, lon1, lat2, lon2) {
  const phi1 = (lat1 * Math.PI) / 180
  const phi2 = (lat2 * Math.PI) / 180
  const deltaPhi = ((lat2 - lat1) * Math.PI) / 180
  const deltaLambda = ((lon2 - lon1) * Math.PI) / 180

  const a =
    Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
    Math.cos(phi1) *
      Math.cos(phi2) *
      Math.sin(deltaLambda / 2) *
      Math.sin(deltaLambda / 2)

  return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}
