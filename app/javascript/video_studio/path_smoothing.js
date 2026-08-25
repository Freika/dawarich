// Bounded Chaikin corner-cutting for GPS polylines: sharp vertices become
// short arcs so the head marker steers through corners instead of pivoting.
// The cut distance is capped in meters, so sparse tracks keep their shape
// (a 1 km leg is not redrawn 250 m early), and vertices whose edges are
// already shorter than a video pixel pass through untouched.
import { haversineDistance } from "video_studio/geo"

const DEFAULT_ITERATIONS = 2
const DEFAULT_MAX_CORNER_M = 30
const DEFAULT_MIN_EDGE_M = 12

function edgeMeters(a, b) {
  return haversineDistance(a[1], a[0], b[1], b[0])
}

function towards(from, to, t) {
  return [from[0] + (to[0] - from[0]) * t, from[1] + (to[1] - from[1]) * t]
}

function cutRatio(edgeLen, maxCornerM) {
  return edgeLen > 0 ? Math.min(0.25, maxCornerM / edgeLen) : 0
}

export function smoothSegmentCoords(
  coords,
  {
    iterations = DEFAULT_ITERATIONS,
    maxCornerM = DEFAULT_MAX_CORNER_M,
    minEdgeM = DEFAULT_MIN_EDGE_M,
  } = {},
) {
  if (!Array.isArray(coords) || coords.length < 3) return coords

  let current = coords
  for (let round = 0; round < iterations; round += 1) {
    const out = [current[0]]
    for (let i = 1; i < current.length - 1; i += 1) {
      const vertex = current[i]
      const prev = current[i - 1]
      const next = current[i + 1]
      const lenPrev = edgeMeters(prev, vertex)
      const lenNext = edgeMeters(vertex, next)
      if (lenPrev < minEdgeM && lenNext < minEdgeM) {
        out.push(vertex)
      } else {
        out.push(towards(vertex, prev, cutRatio(lenPrev, maxCornerM)))
        out.push(towards(vertex, next, cutRatio(lenNext, maxCornerM)))
      }
    }
    out.push(current[current.length - 1])
    current = out
  }
  return current
}
