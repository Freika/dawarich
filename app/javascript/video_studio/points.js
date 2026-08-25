// Normalises the map's points into the { lat, lon, time } shape the HUD clock
// and the stats card expect. The map hands out either GeoJSON features or raw
// point objects depending on which loader ran, and timestamps arrive as unix
// seconds, unix milliseconds, or an ISO string — the same spread
// ReplayManager already copes with.
const SECONDS_CUTOFF = 10_000_000_000

// The points API serialises latitude/longitude as decimal STRINGS, so every
// candidate goes through Number() — comparing a string against Number.isFinite
// silently drops the whole track.
function coordinatesOf(point) {
  if (Array.isArray(point?.geometry?.coordinates)) {
    const [lon, lat] = point.geometry.coordinates
    return { lat: Number(lat), lon: Number(lon) }
  }
  if (point?.longitude !== undefined && point?.latitude !== undefined) {
    return { lat: Number(point.latitude), lon: Number(point.longitude) }
  }
  if (point?.lon !== undefined && point?.lat !== undefined) {
    return { lat: Number(point.lat), lon: Number(point.lon) }
  }
  return null
}

function isoTimeOf(point) {
  const raw = point?.properties?.timestamp ?? point?.timestamp
  if (raw == null) return null

  if (typeof raw === "string") {
    const parsed = Date.parse(raw)
    return Number.isNaN(parsed) ? null : new Date(parsed).toISOString()
  }
  if (typeof raw !== "number" || !Number.isFinite(raw)) return null

  return new Date(raw < SECONDS_CUTOFF ? raw * 1000 : raw).toISOString()
}

// Timeless points are kept: the stats card still measures their distance, and
// the HUD degrades to a distance-only readout when no point carries a time.
export function toVideoPoints(points) {
  if (!Array.isArray(points)) return []

  return points.flatMap((point) => {
    const coordinates = coordinatesOf(point)
    if (
      !coordinates ||
      !Number.isFinite(coordinates.lat) ||
      !Number.isFinite(coordinates.lon)
    ) {
      return []
    }
    return [{ ...coordinates, time: isoTimeOf(point) }]
  })
}
