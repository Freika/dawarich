import { RouteSegmenter } from "./shared_route_segmenter.js"

const colors = [
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
export function publicRoutes(points, options) {
  const groups = new Map()
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: options.zone || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
  for (const [longitude, latitude, timestamp] of points) {
    const day = options.by_day
      ? formatter.format(new Date(timestamp * 1000))
      : ""
    if (!groups.has(day)) groups.set(day, [])
    groups.get(day).push({ longitude, latitude, timestamp })
  }
  const features = []
  for (const [index, [day, group]] of [...groups].sort().entries()) {
    const routes = RouteSegmenter.pointsToRoutes(group, {
      distanceThresholdMeters: options.meters,
      timeThresholdMinutes: options.minutes,
    })
    for (const feature of routes.features) {
      feature.properties.day = day
      feature.properties.color = colors[index % colors.length]
      features.push(feature)
    }
  }
  return { type: "FeatureCollection", features }
}
