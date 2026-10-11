const SOURCE = "native-enrichment-matches"
const LAYER = SOURCE
const DEBOUNCE_MS = 400

export function createEnrichmentTool({
  map,
  pushEvent,
  createPopup,
  root,
  reader,
  library,
  timers = globalThis,
  debounceMs = DEBOUNCE_MS,
  loadResults = () => import("./enrichment_results.js"),
}) {
  let results,
    loading,
    generation = 0
  function renderResults(rows) {
    if (results) {
      results.replace(rows)
      return Promise.resolve()
    }
    if (!rows.length) return Promise.resolve()
    const current = generation
    loading ??= loadResults()
    return loading
      .then(({ createEnrichmentResults }) => {
        if (destroyed || current !== generation) return
        results ??= createEnrichmentResults({
          root,
          reader,
          map,
          library,
          timers,
          pushEvent,
        })
        results.replace(rows)
      })
      .catch(() => {
        loading = null
      })
  }
  let destroyed = false
  let timer = null
  let popup = null

  const closePopup = () => {
    popup?.remove()
    popup = null
    results?.closePopup()
  }

  const onEnter = (event) => {
    closePopup()
    const feature = event.features?.[0]
    if (feature && !destroyed) {
      if (createPopup) popup = createPopup(feature)
      else results?.showPopup(feature.properties.id)
    }
  }

  function clear() {
    generation++
    results?.clear()
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
    const rendered = renderResults(rows)
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
    return rendered
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    if (timer !== null) timers.clearTimeout(timer)
    timer = null
    clear()
    results?.destroy()
  }

  return { rangeChanged, matches, clear, destroy }
}
