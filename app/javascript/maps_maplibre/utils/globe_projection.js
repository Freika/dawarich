export function globeEnabled(setting) {
  return setting === true || setting === "true"
}

export function applyGlobeProjection(map) {
  map.setProjection({ type: "globe" })
  map.setSky({
    "atmosphere-blend": ["interpolate", ["linear"], ["zoom"], 0, 1, 5, 1, 7, 0],
  })
}
