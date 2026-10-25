import { RouteSegmenter } from "./route_segmenter"

const PALETTE = [
  "#6366F1",
  "#F43F5E",
  "#10B981",
  "#F59E0B",
  "#0EA5E9",
  "#A855F7",
  "#F97316",
  "#14B8A6",
  "#EC4899",
  "#84CC16",
  "#06B6D4",
  "#D946EF",
]

export function generateDayPalette(numDays) {
  if (numDays === 1) return [PALETTE[0]]
  if (numDays <= PALETTE.length) return PALETTE.slice(0, numDays)

  return Array.from({ length: numDays }, (_, i) => {
    const hue = (i * (360 / numDays)) % 360
    return `hsl(${hue}, 70%, 55%)`
  })
}

export function buildDayRouteCollections(pointsByDay, options = {}) {
  const dayKeys = Object.keys(pointsByDay).sort()
  const colors = generateDayPalette(dayKeys.length)

  return dayKeys.flatMap((dayKey, index) => {
    const points = pointsByDay[dayKey]
    if (points.length < 2) return []

    const routes = RouteSegmenter.pointsToRoutes(points, {
      distanceThresholdMeters: options.distanceThresholdMeters || 500,
      timeThresholdMinutes: options.timeThresholdMinutes || 60,
    })
    for (const feature of routes.features) {
      feature.properties.color = colors[index]
      feature.properties.dayKey = dayKey
    }
    return [routes]
  })
}
