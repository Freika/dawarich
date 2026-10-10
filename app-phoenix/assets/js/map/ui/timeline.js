const SOURCE = "native-timeline-hover"
const LAYER = "native-timeline-hover-line"

export function createTimelineHover({ map }) {
  let destroyed = false

  function clear() {
    if (map.getLayer(LAYER)) map.removeLayer(LAYER)
    if (map.getSource(SOURCE)) map.removeSource(SOURCE)
  }

  function hover(feature) {
    if (destroyed || !feature?.geometry) return clear()
    const source = map.getSource(SOURCE)
    if (source) return source.setData(feature)
    map.addSource(SOURCE, { type: "geojson", data: feature })
    map.addLayer({
      id: LAYER,
      type: "line",
      source: SOURCE,
      paint: { "line-color": "#0ea5e9", "line-width": 6, "line-opacity": 0.8 },
    })
  }

  function destroy() {
    destroyed = true
    clear()
  }

  return { hover, clear, config: () => clear(), destroy }
}
