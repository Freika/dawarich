const GROUPS = [
  ["hexagons"],
  ["areas"],
  ["native-selected-track"],
  ["flights"],
  ["visits"],
  ["places"],
  ["photos"],
  ["family"],
  ["tracks-mvt"],
  ["anomalies"],
  ["heatmap", "points-mvt"],
  ["recent-point"],
  ["replay"],
  ["fog"],
  ["scratch"],
]

function rank(id) {
  return GROUPS.findIndex((prefixes) =>
    prefixes.some((prefix) => id === prefix || id.startsWith(`${prefix}-`)),
  )
}

export function layerAbove(map, id) {
  const own = rank(id)
  if (own < 0) return undefined
  for (const layer of map.getStyle?.()?.layers ?? []) {
    if (rank(layer.id) > own) return layer.id
  }
  return undefined
}
