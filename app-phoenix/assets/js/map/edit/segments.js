const SOURCE = "native-segment-highlight"
const LAYER = "native-segment-highlight-line"

export function segmentLine(path, { start_index: first, end_index: last }) {
  if (!Number.isInteger(first) || !Number.isInteger(last) || last <= first)
    return null
  const line = path.slice(first, last + 1)
  return line.length >= 2 ? line : null
}

export function createSegmentHighlight({ map }) {
  let destroyed = false

  function clear() {
    if (map.getLayer(LAYER)) map.removeLayer(LAYER)
    if (map.getSource(SOURCE)) map.removeSource(SOURCE)
  }

  function show(path, segment) {
    if (destroyed) return
    const line = segmentLine(path, segment)
    if (!line) return clear()
    const data = {
      type: "Feature",
      geometry: { type: "LineString", coordinates: line },
      properties: {},
    }
    const source = map.getSource(SOURCE)
    if (source) return source.setData(data)
    map.addSource(SOURCE, { type: "geojson", data })
    map.addLayer({
      id: LAYER,
      type: "line",
      source: SOURCE,
      paint: { "line-color": "#f59e0b", "line-width": 6 },
    })
  }

  function destroy() {
    destroyed = true
    clear()
  }

  return { show, clear, destroy }
}
