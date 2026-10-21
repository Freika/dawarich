const rectangle = "selection-source"
const selected = "selected-points-source"
const layers = [
  "selection-fill",
  "selection-outline",
  "selected-points-highlight",
  "selected-points",
]
const data = (features = []) => ({ type: "FeatureCollection", features })

export function createSelectionDrawing(map) {
  function ensure(source, features, definitions) {
    const existing = map.getSource(source)
    if (existing) return existing.setData(data(features))
    map.addSource(source, { type: "geojson", data: data(features) })
    for (const definition of definitions)
      map.addLayer({ source, ...definition })
  }
  function draw(bounds) {
    const features = bounds
      ? [
          {
            type: "Feature",
            properties: {},
            geometry: {
              type: "Polygon",
              coordinates: [
                [
                  [bounds.minLng, bounds.minLat],
                  [bounds.maxLng, bounds.minLat],
                  [bounds.maxLng, bounds.maxLat],
                  [bounds.minLng, bounds.maxLat],
                  [bounds.minLng, bounds.minLat],
                ],
              ],
            },
          },
        ]
      : []
    ensure(rectangle, features, [
      {
        id: "selection-fill",
        type: "fill",
        paint: { "fill-color": "#3b82f6", "fill-opacity": 0.1 },
      },
      {
        id: "selection-outline",
        type: "line",
        paint: {
          "line-color": "#3b82f6",
          "line-width": 2,
          "line-dasharray": [2, 2],
        },
      },
    ])
  }
  function highlight(points) {
    const features = points
      .filter(
        (point) =>
          point.longitude != null &&
          point.latitude != null &&
          Number.isFinite(Number(point.longitude)) &&
          Number.isFinite(Number(point.latitude)),
      )
      .map((point) => ({
        type: "Feature",
        properties: { id: point.id },
        geometry: {
          type: "Point",
          coordinates: [Number(point.longitude), Number(point.latitude)],
        },
      }))
    ensure(selected, features, [
      {
        id: "selected-points-highlight",
        type: "circle",
        paint: {
          "circle-radius": 8,
          "circle-color": "#ef4444",
          "circle-opacity": 0.3,
        },
      },
      {
        id: "selected-points",
        type: "circle",
        paint: {
          "circle-radius": 5,
          "circle-color": "#ef4444",
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ])
  }
  function clear() {
    for (const id of layers) if (map.getLayer(id)) map.removeLayer(id)
    for (const source of [rectangle, selected])
      if (map.getSource(source)) map.removeSource(source)
  }
  return { draw, highlight, clear }
}
