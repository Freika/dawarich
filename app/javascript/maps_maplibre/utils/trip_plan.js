// Helpers for drawing a trip plan (see Trips::PlanGeojson): stops keep the
// numbers of the plan card and take their day's colour.

const stops = (plan) =>
  plan.features.filter((feature) => feature.properties.kind === "stop")

export function planDayCount(plan) {
  const days = stops(plan).map((feature) => feature.properties.day)
  return days.length ? Math.max(...days) + 1 : 0
}

export function planMarkers(plan, palette) {
  return stops(plan).map((feature) => ({
    coordinates: feature.geometry.coordinates,
    number: feature.properties.number,
    name: feature.properties.name,
    color: palette[feature.properties.day % palette.length],
  }))
}

export function planDayColorExpression(palette) {
  return [
    "match",
    ["get", "day"],
    ...palette.flatMap((color, day) => [day, color]),
    palette[0],
  ]
}

export function planBounds(plan) {
  const coordinates = plan.features.flatMap((feature) =>
    feature.geometry.type === "Point"
      ? [feature.geometry.coordinates]
      : feature.geometry.coordinates,
  )
  if (!coordinates.length) return null
  const lngs = coordinates.map(([lng]) => lng)
  const lats = coordinates.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}
