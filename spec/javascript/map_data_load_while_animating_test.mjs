import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/map_data_manager.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
const translate = (key) => key
const Toast = { error() {} }
const UpgradeBanner = { show() {} }
const flightWindows = (geoJSON) => geoJSON?.windows || []
const isGatedPlan = () => false
const performanceMonitor = { mark() {}, measure() { return 0 } }
const trimOutlierCoords = (coords) => coords
const overlayAwarePadding = () => ({ top: 50, right: 50, bottom: 50, left: 50 })
const maplibregl = {}
`
const { MapDataManager } = await import(
  `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
)

function animatingMap() {
  const handlers = {}
  let styleLoaded = false
  return {
    becomeStyleLoaded() {
      styleLoaded = true
    },
    emit(event) {
      for (const handler of [...(handlers[event] || [])]) handler()
    },
    isStyleLoaded: () => styleLoaded,
    on: (event, handler) => {
      handlers[event] = [...(handlers[event] || []), handler]
    },
    off: (event, handler) => {
      handlers[event] = (handlers[event] || []).filter((h) => h !== handler)
    },
    getContainer: () => ({ getBoundingClientRect: () => null }),
    fitBounds: () => {},
  }
}

function buildManager(map) {
  const empty = { type: "FeatureCollection", features: [] }
  const badge = { classList: new Set(["visible"]) }
  badge.classList.contains = badge.classList.has
  const controller = {
    map,
    dataLoader: {
      fetchMapData: async () => ({
        visits: [],
        visitsGeoJSON: empty,
        areasGeoJSON: empty,
        placesGeoJSON: empty,
        backgroundReady: Promise.resolve(),
      }),
    },
    layerManager: {
      updatePointTileRange: () => {},
      addAllLayers: async () => {},
      setupLayerEventHandlers: () => {},
      getLayer: () => null,
    },
    filterManager: { setAllVisits: () => {} },
    eventHandlers: new Proxy({}, { get: () => () => {} }),
    showProgress: () => {},
    hideProgress: () => {},
    updateLoadingCounts: () => {},
    hasProgressBadgeTarget: false,
    userPlanValue: "pro",
  }
  return new MapDataManager(controller)
}

test("map data finishes loading while a selection animation keeps the map rendering", async () => {
  const map = animatingMap()
  const manager = buildManager(map)

  let finished = false
  const load = manager
    .loadMapData("2026-09-17T00:00:00Z", "2026-09-17T23:59:59Z", {
      fitBounds: false,
    })
    .then(() => {
      finished = true
    })

  map.emit("render")
  map.becomeStyleLoaded()
  for (let frame = 0; frame < 5; frame++) map.emit("render")
  await Promise.race([load, new Promise((resolve) => setTimeout(resolve, 200))])

  assert.equal(
    finished,
    true,
    "loadMapData must not wait for an idle event that never comes",
  )
})
