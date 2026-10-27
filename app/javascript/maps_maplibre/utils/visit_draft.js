export function pointsToVisitDraft(points, mergeThresholdMinutes = 15) {
  if (!points.length) return null
  const ordered = [...points].sort((a, b) => a.timestamp - b.timestamp)
  const stays = [[]]
  for (const point of ordered) {
    const stay = stays[stays.length - 1]
    if (
      stay.length &&
      point.timestamp - stay[stay.length - 1].timestamp >
        mergeThresholdMinutes * 60
    ) {
      stays.push([])
    }
    stays[stays.length - 1].push(point)
  }
  const latest = stays[stays.length - 1]
  const median = (values) => {
    const sorted = values.map(Number).sort((a, b) => a - b)
    const middle = Math.floor(sorted.length / 2)
    return sorted.length % 2
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2
  }
  return {
    lat: median(latest.map((point) => point.latitude)),
    lng: median(latest.map((point) => point.longitude)),
    startedAt: new Date(latest[0].timestamp * 1000).toISOString(),
    endedAt: new Date(latest[latest.length - 1].timestamp * 1000).toISOString(),
    multipleStays: stays.length > 1,
  }
}
