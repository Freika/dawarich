// Devices recording at the same time trace separate paths; drawing them as
// one line zigzags between them. The server names the device to follow.
export function pointsFromDevice(points, trackerId) {
  const device = trackerId || null
  return points.filter((point) => (point.tracker_id || null) === device)
}
