// Maps distance along the route to recorded time, so the HUD can show the
// playhead's date, clock time, and elapsed span. Uses the same gap rule as
// the drawn track: pairs separated by more than the threshold advance time
// but not distance, mirroring the segment jumps that cost no animation time.
import { haversineDistance } from "video_studio/geo"

const DEFAULT_GAP_MINUTES = 60

function isValidTimedPoint(point) {
  return (
    point != null &&
    Number.isFinite(point.lat) &&
    Number.isFinite(point.lon) &&
    Math.abs(point.lat) <= 90 &&
    Math.abs(point.lon) <= 180 &&
    point.time != null &&
    !Number.isNaN(Date.parse(point.time))
  )
}

export function buildRouteClock(
  points,
  { gapMinutes = DEFAULT_GAP_MINUTES } = {},
) {
  const timed = (Array.isArray(points) ? points : [])
    .filter(isValidTimedPoint)
    .map((point) => ({ ...point, ts: Date.parse(point.time) }))
    .sort((a, b) => a.ts - b.ts)
  if (timed.length < 2) return null

  const gapMs = gapMinutes * 60 * 1000
  const entries = [{ dist: 0, ts: timed[0].ts }]
  let dist = 0
  for (let i = 1; i < timed.length; i += 1) {
    const prev = timed[i - 1]
    const point = timed[i]
    if (point.ts - prev.ts <= gapMs) {
      dist += haversineDistance(prev.lat, prev.lon, point.lat, point.lon)
    }
    entries.push({ dist, ts: point.ts })
  }

  return {
    entries,
    totalDistance: dist,
    startTs: entries[0].ts,
    endTs: entries[entries.length - 1].ts,
  }
}

export function timeAtFraction(clock, fraction) {
  const { entries, totalDistance } = clock
  const f = Math.max(0, Math.min(1, fraction))
  const target = f * totalDistance

  for (let i = 1; i < entries.length; i += 1) {
    if (entries[i].dist >= target) {
      const prev = entries[i - 1]
      const span = entries[i].dist - prev.dist
      const t = span > 0 ? (target - prev.dist) / span : 0
      return Math.round(prev.ts + (entries[i].ts - prev.ts) * t)
    }
  }
  return clock.endTs
}
