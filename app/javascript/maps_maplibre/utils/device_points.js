// Devices recording at the same time trace separate paths; drawing them as
// one line zigzags between them. The server names the devices to follow;
// consecutive devices — GPX segments, imported activities — are all named.
export function pointsFromDevice(points, trackerIds) {
  const devices = new Set((trackerIds || []).map((id) => id || null))
  if (!devices.size) return points
  return points.filter((point) => devices.has(point.tracker_id || null))
}
