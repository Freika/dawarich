// Follow-mode camera: the center is the mean of the route coordinates in a
// trailing distance window behind the pen tip, so the camera glides through
// corners instead of snapping, and drifts smoothly across segment jumps
// (which cost no distance, letting both tails share the window).
import { sliceAtFraction } from "video_studio/route_timeline"

const DEFAULT_WINDOW_M = 400

// Linear interpolation between two camera poses, for the summary pull-out.
export function lerpCamera(from, to, t) {
  const f = Math.max(0, Math.min(1, t))
  return {
    center: [
      from.center[0] + (to.center[0] - from.center[0]) * f,
      from.center[1] + (to.center[1] - from.center[1]) * f,
    ],
    zoom: from.zoom + (to.zoom - from.zoom) * f,
  }
}

export function followCenter(
  timeline,
  fraction,
  { windowM = DEFAULT_WINDOW_M } = {},
) {
  const { entries, totalDistance } = timeline
  if (entries.length === 0) return null

  const slice = sliceAtFraction(timeline, fraction)
  if (!slice.head) return null
  if (windowM <= 0) return slice.head

  const target = Math.max(0, Math.min(1, fraction)) * totalDistance
  const from = target - windowM

  let sumLon = slice.head[0]
  let sumLat = slice.head[1]
  let count = 1
  for (const entry of entries) {
    if (entry.dist > target) break
    if (entry.dist < from) continue
    sumLon += entry.coord[0]
    sumLat += entry.coord[1]
    count += 1
  }
  return [sumLon / count, sumLat / count]
}
