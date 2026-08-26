// Distance-paced animation timeline for a track FeatureCollection (the
// posterTrack shape: LineString segments split on time gaps, stray Points).
// The route draws at constant speed along its own length; jumps between
// disjoint segments cost no animation time.
import { haversineDistance } from "video_studio/geo"
import { smoothSegmentCoords } from "video_studio/path_smoothing"

export function buildRouteTimeline(trackGeojson, { smooth = false } = {}) {
  const entries = []
  let totalDistance = 0
  const features = trackGeojson?.features ?? []
  let seg = 0
  for (const feature of features) {
    const geometry = feature?.geometry
    if (geometry?.type !== "LineString") continue
    let coordinates = geometry.coordinates ?? []
    if (coordinates.length < 2) continue
    if (smooth) coordinates = smoothSegmentCoords(coordinates)
    for (let i = 0; i < coordinates.length; i += 1) {
      const coord = coordinates[i]
      if (i > 0) {
        const prev = coordinates[i - 1]
        totalDistance += haversineDistance(prev[1], prev[0], coord[1], coord[0])
      }
      entries.push({ coord, dist: totalDistance, seg })
    }
    seg += 1
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

// The sub-path between two distances along the route — the "fresh" window
// that stays at full brightness behind the pen while older stretches dim.
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
