const SOURCE = "native-enrichment-matches"
const LAYER = SOURCE
const DEBOUNCE_MS = 400

export function createEnrichmentTool({
  map,
  pushEvent,
  createPopup,
  timers = globalThis,
  debounceMs = DEBOUNCE_MS,
}) {
  let destroyed = false
  let timer = null
  let popup = null

  const closePopup = () => {
    popup?.remove()
    popup = null
  }

  const onEnter = (event) => {
    closePopup()
    const feature = event.features?.[0]
    if (feature && !destroyed) popup = createPopup(feature)
  }

  function clear() {
    closePopup()
    if (map.getLayer(LAYER)) {
      map.off("mouseenter", LAYER, onEnter)
      map.off("mouseleave", LAYER, closePopup)
      map.removeLayer(LAYER)
    }
    if (map.getSource(SOURCE)) map.removeSource(SOURCE)
  }

  function rangeChanged(params) {
    if (destroyed) return
    clear()
    if (timer !== null) timers.clearTimeout(timer)
    timer = timers.setTimeout(() => {
      timer = null
      if (!destroyed) pushEvent("enrichment:scan", params)
    }, debounceMs)
  }

  function matches({ matches: rows = [] }) {
    if (destroyed) return
    clear()
    const features = rows
      .filter(
        (row) =>
          Number.isFinite(Number(row.latitude)) &&
          Number.isFinite(Number(row.longitude)),
      )
      .map((row) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [Number(row.longitude), Number(row.latitude)],
        },
        properties: { id: row.immich_asset_id },
      }))
    map.addSource(SOURCE, {
      type: "geojson",
      data: { type: "FeatureCollection", features },
    })
    map.addLayer({
      id: LAYER,
      type: "circle",
      source: SOURCE,
      paint: { "circle-radius": 6, "circle-color": "#a855f7" },
    })
    map.on("mouseenter", LAYER, onEnter)
    map.on("mouseleave", LAYER, closePopup)
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    if (timer !== null) timers.clearTimeout(timer)
    timer = null
    clear()
  }

  return { rangeChanged, matches, destroy }
}
