import { haversineDistance } from "./geo.js"
import { smoothSegmentCoords } from "./path_smoothing.js"

function startTimeOf(feature) {
  const raw = feature?.properties?.start_at ?? feature?.properties?.startTime
  if (raw == null) return null
  if (typeof raw === "number") return Number.isFinite(raw) ? raw : null
  const parsed = Date.parse(raw)
  return Number.isNaN(parsed) ? null : parsed
}

function chronological(features) {
  const timed = features.map((feature) => ({
    feature,
    startedAt: startTimeOf(feature),
  }))
  if (timed.some(({ startedAt }) => startedAt === null)) return features
  return timed
    .sort((a, b) => a.startedAt - b.startedAt)
    .map(({ feature }) => feature)
}

export function buildRouteTimeline(trackGeojson, { smooth = false } = {}) {
  const entries = []
  let totalDistance = 0
  const features = chronological(
    (trackGeojson?.features ?? []).filter((feature) =>
      ["LineString", "MultiLineString"].includes(feature?.geometry?.type),
    ),
  )
  let seg = 0
  for (const feature of features) {
    const lines =
      feature.geometry.type === "MultiLineString"
        ? (feature.geometry.coordinates ?? [])
        : [feature.geometry.coordinates ?? []]
    for (const line of lines) {
      let coordinates = line
      if (coordinates.length < 2) continue
      if (smooth) coordinates = smoothSegmentCoords(coordinates)
      for (let i = 0; i < coordinates.length; i += 1) {
        const coord = coordinates[i]
        if (i > 0) {
          const prev = coordinates[i - 1]
          totalDistance += haversineDistance(
            prev[1],
            prev[0],
            coord[1],
            coord[0],
          )
        }
        entries.push({ coord, dist: totalDistance, seg })
      }
      seg += 1
    }
  }
  return { entries, totalDistance }
}

function lerpCoord(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
}

function lineFeature(coordinates) {
  return {
    type: "Feature",
    properties: {},
    geometry: { type: "LineString", coordinates },
  }
}

export function sliceWindow(timeline, fromDist, toDist) {
  const { entries, totalDistance } = timeline
  if (entries.length === 0) return { features: [] }
  const from = Math.max(0, Math.min(totalDistance, fromDist))
  const to = Math.max(from, Math.min(totalDistance, toDist))
  if (to <= from) return { features: [] }

  const features = []
  let current = []
  for (let i = 1; i < entries.length; i += 1) {
    const prev = entries[i - 1]
    const entry = entries[i]
    if (prev.seg !== entry.seg) {
      if (current.length >= 2) features.push(lineFeature(current))
      current = []
      continue
    }
    const start = Math.max(prev.dist, from)
    const end = Math.min(entry.dist, to)
    const span = entry.dist - prev.dist
    if (end <= start || span <= 0) continue
    if (current.length === 0) {
      current.push(
        lerpCoord(prev.coord, entry.coord, (start - prev.dist) / span),
      )
    }
    current.push(lerpCoord(prev.coord, entry.coord, (end - prev.dist) / span))
  }
  if (current.length >= 2) features.push(lineFeature(current))
  return { features }
}

export function sliceAtFraction(timeline, fraction) {
  const { entries, totalDistance } = timeline
  if (entries.length === 0) return { features: [], head: null, distance: 0 }

  const f = Math.max(0, Math.min(1, fraction))
  const target = f * totalDistance

  const features = []
  let current = []
  let head = entries[0].coord
  let done = false

  for (let i = 0; i < entries.length && !done; i += 1) {
    const entry = entries[i]
    const isNewSegment = current.length > 0 && entry.seg !== entries[i - 1].seg
    if (isNewSegment) {
      if (current.length >= 2) features.push(lineFeature(current))
      current = []
    }
    if (entry.dist <= target) {
      current.push(entry.coord)
      head = entry.coord
    } else {
      const prev = entries[i - 1]
      if (prev && prev.seg === entry.seg) {
        const span = entry.dist - prev.dist
        const t = span > 0 ? (target - prev.dist) / span : 0
        if (t > 0) {
          head = lerpCoord(prev.coord, entry.coord, t)
          current.push(head)
        }
      }
      done = true
    }
  }
  if (current.length >= 2) features.push(lineFeature(current))

  return { features, head, distance: target }
}
