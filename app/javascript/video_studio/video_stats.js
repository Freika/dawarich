// Route statistics for the video HUD and end card. Distance and moving time
// skip pairs separated by more than the gap threshold — the same split rule
// pointsToTrackGeoJSON uses for the drawn track.
import { haversineDistance } from "video_studio/geo"

const DEFAULT_GAP_MINUTES = 60
const KM_PER_MILE = 1.609344

function isValidPoint(point) {
  return (
    point != null &&
    Number.isFinite(point.lat) &&
    Number.isFinite(point.lon) &&
    Math.abs(point.lat) <= 90 &&
    Math.abs(point.lon) <= 180
  )
}

export function computeTrackStats(
  points,
  { gapMinutes = DEFAULT_GAP_MINUTES } = {},
) {
  const valid = (Array.isArray(points) ? points : []).filter(isValidPoint)

  const timed = []
  const timeless = []
  for (const point of valid) {
    const ts = point.time ? Date.parse(point.time) : Number.NaN
    if (Number.isNaN(ts)) timeless.push(point)
    else timed.push({ ...point, ts })
  }
  timed.sort((a, b) => a.ts - b.ts)

  const gapMs = gapMinutes * 60 * 1000
  let distanceM = 0
  let movingTimeMs = 0

  for (let i = 1; i < timed.length; i += 1) {
    const dt = timed[i].ts - timed[i - 1].ts
    if (dt > gapMs) continue
    distanceM += haversineDistance(
      timed[i - 1].lat,
      timed[i - 1].lon,
      timed[i].lat,
      timed[i].lon,
    )
    movingTimeMs += dt
  }
  for (let i = 1; i < timeless.length; i += 1) {
    distanceM += haversineDistance(
      timeless[i - 1].lat,
      timeless[i - 1].lon,
      timeless[i].lat,
      timeless[i].lon,
    )
  }

  const avgSpeedKmh =
    movingTimeMs > 0
      ? distanceM / 1000 / (movingTimeMs / (60 * 60 * 1000))
      : null

  return { distanceM, movingTimeMs, avgSpeedKmh, pointCount: valid.length }
}

export function formatDistance(meters, units = "km") {
  if (!Number.isFinite(meters)) return "—"
  if (units === "mi") return `${(meters / 1000 / KM_PER_MILE).toFixed(1)} mi`
  if (meters < 1000) return `${Math.round(meters)} m`
  return `${(meters / 1000).toFixed(1)} km`
}

export function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms <= 0) return "—"
  const totalSeconds = Math.round(ms / 1000)
  if (totalSeconds < 60) return `${totalSeconds} s`
  const totalMinutes = Math.round(totalSeconds / 60)
  if (totalMinutes < 60) return `${totalMinutes} min`
  const hours = Math.floor(totalMinutes / 60)
  if (hours >= 48) return `${Math.round(hours / 24)} days`
  return `${hours} h ${totalMinutes - hours * 60} min`
}

export function formatSpeed(kmh, units = "km") {
  if (!Number.isFinite(kmh)) return "—"
  if (units === "mi") return `${(kmh / KM_PER_MILE).toFixed(1)} mph`
  return `${kmh.toFixed(1)} km/h`
}

// Below walking pace the average is an artifact of month-long location
// history rather than a route, so the speed row is dropped.
const MIN_MEANINGFUL_SPEED_KMH = 1

// Returns { label, value } rows for the studio's summary chips. Labels are
// injected so the caller can localise them; the defaults keep the module
// usable on its own.
const DEFAULT_STAT_LABELS = {
  distance: "Distance",
  duration: "Duration",
  avgSpeed: "Avg speed",
}

export function buildStatRows(stats, units = "km", labels = {}) {
  const text = { ...DEFAULT_STAT_LABELS, ...labels }
  const rows = [
    { label: text.distance, value: formatDistance(stats.distanceM, units) },
    { label: text.duration, value: formatDuration(stats.movingTimeMs) },
    {
      label: text.avgSpeed,
      value:
        stats.avgSpeedKmh >= MIN_MEANINGFUL_SPEED_KMH
          ? formatSpeed(stats.avgSpeedKmh, units)
          : "—",
    },
  ]
  return rows.filter((row) => row.value !== "—")
}
