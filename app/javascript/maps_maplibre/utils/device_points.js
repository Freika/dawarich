export function pointsFromDevice(points, windows) {
  if (!windows?.length) return points

  return points.filter((point) => {
    const timestamp = Number(point.timestamp)
    let start = 0
    let end = windows.length - 1

    while (start <= end) {
      const index = Math.floor((start + end) / 2)
      const window = windows[index]
      if (timestamp < window.start_at) {
        end = index - 1
      } else if (timestamp > window.end_at) {
        start = index + 1
      } else {
        return (point.tracker_id || "") === (window.tracker_id || "")
      }
    }
    return false
  })
}
