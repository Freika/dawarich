const SOURCE = "native-area-preview"
const LAYERS = ["native-area-preview-fill", "native-area-preview-line"]

export function circlePolygon(latitude, longitude, radius, steps = 64) {
  const ring = []
  for (let i = 0; i <= steps; i++) {
    const angle = ((i % steps) / steps) * 2 * Math.PI
    const dLat = (radius * Math.cos(angle)) / 111320
    const dLon =
      (radius * Math.sin(angle)) /
      (111320 * Math.cos((latitude * Math.PI) / 180))
    ring.push([longitude + dLon, latitude + dLat])
  }
  return {
    type: "Feature",
    geometry: { type: "Polygon", coordinates: [ring] },
    properties: {},
  }
}

const round = (value) => Math.round(value * 1e6) / 1e6

export function createAreaEditor({ map, pushEvent }) {
  let destroyed = false
  let click = null

  function disarm() {
    if (click) map.off("click", click)
    click = null
    map.getCanvas().style.cursor = ""
  }

  function arm() {
    if (destroyed) return
    disarm()
    click = (event) => {
      disarm()
      pushEvent("area:new", {
        latitude: round(event.lngLat.lat),
        longitude: round(event.lngLat.lng),
      })
    }
    map.on("click", click)
    map.getCanvas().style.cursor = "crosshair"
  }

  function preview({ latitude, longitude, radius }) {
    if (destroyed) return
    const metres = Number(radius)
    const features =
      Number.isFinite(metres) && metres > 0
        ? [circlePolygon(Number(latitude), Number(longitude), metres)]
        : []
    const data = { type: "FeatureCollection", features }
    const source = map.getSource(SOURCE)
    if (source) return source.setData(data)
    map.addSource(SOURCE, { type: "geojson", data })
    map.addLayer({
      id: LAYERS[0],
      type: "fill",
      source: SOURCE,
      paint: { "fill-color": "#3b82f6", "fill-opacity": 0.2 },
    })
    map.addLayer({
      id: LAYERS[1],
      type: "line",
      source: SOURCE,
      paint: { "line-color": "#3b82f6", "line-width": 2 },
    })
  }

  function clear() {
    for (const id of LAYERS) if (map.getLayer(id)) map.removeLayer(id)
    if (map.getSource(SOURCE)) map.removeSource(SOURCE)
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    disarm()
    clear()
  }

  return { arm, disarm, preview, clear, destroy }
}
