const heatmapPaint = {
  "heatmap-weight": 0.5,
  "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 0, 1, 15, 1.5],
  "heatmap-color": [
    "interpolate",
    ["linear"],
    ["heatmap-density"],
    0,
    "rgba(0,0,255,0)",
    0.4,
    "rgb(0,0,255)",
    0.6,
    "rgb(0,255,255)",
    0.7,
    "rgb(0,255,0)",
    0.8,
    "rgb(255,255,0)",
    1,
    "rgb(255,0,0)",
  ],
  "heatmap-radius": [
    "interpolate",
    ["exponential", 1.5],
    ["zoom"],
    10,
    8,
    13,
    15,
    15,
    25,
  ],
  "heatmap-opacity": 0.8,
}
export function createMonthPoints({ map }) {
  function clear() {
    for (const id of ["stat-heatmap", "stat-circles"])
      if (map.getLayer(id)) map.removeLayer(id)
    if (map.getSource("stat-points")) map.removeSource("stat-points")
  }
  return {
    show(points, layer) {
      const coordinates = points
        .map((point) => [
          Number.parseFloat(point.longitude),
          Number.parseFloat(point.latitude),
        ])
        .filter(
          ([lng, lat]) =>
            Number.isFinite(lng) &&
            Number.isFinite(lat) &&
            lng !== 0 &&
            lat !== 0,
        )
      clear()
      if (!coordinates.length) return
      map.addSource("stat-points", {
        type: "geojson",
        data: {
          type: "FeatureCollection",
          features: coordinates.map((coordinate) => ({
            type: "Feature",
            geometry: { type: "Point", coordinates: coordinate },
            properties: {},
          })),
        },
      })
      map.addLayer({
        id: "stat-heatmap",
        type: "heatmap",
        source: "stat-points",
        layout: { visibility: layer === "heatmap" ? "visible" : "none" },
        paint: heatmapPaint,
      })
      map.addLayer({
        id: "stat-circles",
        type: "circle",
        source: "stat-points",
        layout: { visibility: layer === "points" ? "visible" : "none" },
        paint: {
          "circle-radius": 3,
          "circle-color": "#570df8",
          "circle-opacity": 0.6,
          "circle-stroke-width": 1,
          "circle-stroke-color": "#570df8",
          "circle-stroke-opacity": 0.8,
        },
      })
      const bounds = coordinates.reduce(
        ([min, max], point) => [
          [Math.min(min[0], point[0]), Math.min(min[1], point[1])],
          [Math.max(max[0], point[0]), Math.max(max[1], point[1])],
        ],
        [coordinates[0], coordinates[0]],
      )
      map.fitBounds(bounds, { padding: 40, maxZoom: 14, duration: 0 })
    },
    destroy: clear,
  }
}
