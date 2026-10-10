export function fitRoute({ map, geometry, padding }) {
  const lines =
    geometry?.type === "MultiLineString"
      ? geometry.coordinates
      : [geometry?.coordinates || []]
  const points = lines
    .flat()
    .filter((point) => Array.isArray(point) && point.length >= 2)
  if (points.length === 0) return false
  const lons = points.map(([lon]) => lon)
  const lats = points.map(([, lat]) => lat)
  map.fitBounds(
    [
      [Math.min(...lons), Math.min(...lats)],
      [Math.max(...lons), Math.max(...lats)],
    ],
    { padding: padding() },
  )
  return true
}
