export function hexagonLayerConfigs(sourceId) {
  return [
    {
      id: "hexagons-fill",
      type: "fill",
      source: sourceId,
      paint: {
        "fill-color": [
          "interpolate",
          ["linear"],
          ["get", "log_count"],
          0,
          "#1E3A8A",
          1,
          "#3B82F6",
          2,
          "#06B6D4",
          3,
          "#0D9488",
          4,
          "#F59E0B",
        ],
        "fill-opacity": 0.6,
      },
    },
    {
      id: "hexagons-outline",
      type: "line",
      source: sourceId,
      paint: {
        "line-color": [
          "case",
          ["boolean", ["feature-state", "hover"], false],
          "rgba(255,255,255,0.95)",
          "rgba(255,255,255,0.35)",
        ],
        "line-width": [
          "case",
          ["boolean", ["feature-state", "hover"], false],
          2,
          1,
        ],
      },
    },
  ]
}
