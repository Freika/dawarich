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
class LngLatBounds {
  constructor() { this.coordinates = [] }
  extend(coord) { this.coordinates.push(coord); return this }
  isEmpty() { return this.coordinates.length === 0 }
  getSouthWest() { return this.coordinates[0] }
  getNorthEast() { return this.coordinates.at(-1) }
}
const maplibregl = { LngLatBounds }
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
const { MapDataManager } = await import(moduleUrl)

globalThis.document = { querySelector: () => null }

test("GPS-only tile history fits the map from bounded metadata", async () => {
  const fits = []
  const boundsRequests = []
  const empty = { type: "FeatureCollection", features: [] }
  const controller = {
    map: {
      getContainer: () => ({ getBoundingClientRect: () => null }),
      fitBounds: (bounds, options) => fits.push({ bounds, options }),
    },
    dataLoader: {
      fetchMapData: async () => ({
        visits: [],
        visitsGeoJSON: empty,
        areasGeoJSON: empty,
        placesGeoJSON: empty,
        backgroundReady: Promise.resolve(),
      }),
    },
    api: {
      fetchHistoryBounds: async (range) => {
        boundsRequests.push(range)
        return {
          min_lng: 12.9,
          min_lat: 52.3,
          max_lng: 13.8,
          max_lat: 52.7,
        }
      },
    },
    layerManager: {
      updatePointTileRange() {},
      getLayer: () => null,
    },
    filterManager: { setAllVisits() {} },
    showProgress() {},
    hideProgress() {},
    hasProgressBadgeTarget: false,
  }
  const manager = new MapDataManager(controller)
  manager._setupLayers = async () => {}

  await manager.loadMapData("2026-06-01", "2026-06-30", {
    showLoading: false,
  })

  assert.equal(fits.length, 1)
  assert.deepEqual(boundsRequests, [
    { start_at: "2026-06-01", end_at: "2026-06-30" },
  ])
  assert.deepEqual(fits[0].bounds.coordinates, [
    [12.9, 52.3],
    [13.8, 52.7],
  ])
  assert.equal(fits[0].options.maxZoom, 15)
})

test("history bounds take precedence over a distant visit", async () => {
  const fits = []
  const empty = { type: "FeatureCollection", features: [] }
  let boundsRequests = 0
  let historyBounds = {
    min_lng: 13.4,
    min_lat: 52.5,
    max_lng: 13.5,
    max_lat: 52.6,
  }
  const controller = {
    map: {
      getContainer: () => ({ getBoundingClientRect: () => null }),
      fitBounds: (bounds) => fits.push(bounds.coordinates),
    },
    dataLoader: {
      fetchMapData: async () => ({
        visits: [],
        visitsGeoJSON: {
          type: "FeatureCollection",
          features: [
            {
              type: "Feature",
              geometry: { type: "Point", coordinates: [-73.9, 40.7] },
            },
          ],
        },
        areasGeoJSON: empty,
        placesGeoJSON: empty,
        backgroundReady: Promise.resolve(),
      }),
    },
    api: {
      fetchHistoryBounds: async () => {
        boundsRequests += 1
        return historyBounds
      },
    },
    layerManager: {
      updatePointTileRange() {},
      getLayer: () => null,
    },
    filterManager: { setAllVisits() {} },
    showProgress() {},
    hideProgress() {},
    hasProgressBadgeTarget: false,
  }
  const manager = new MapDataManager(controller)
  manager._setupLayers = async () => {}

  await manager.loadMapData("2026-06-01", "2026-06-30", {
    showLoading: false,
  })

  assert.deepEqual(fits, [
    [
      [13.4, 52.5],
      [13.5, 52.6],
    ],
  ])
  assert.equal(boundsRequests, 1)

  historyBounds = null
  await manager.loadMapData("2026-07-01", "2026-07-31", {
    showLoading: false,
  })
  assert.deepEqual(fits[1], [[-73.9, 40.7]])
  assert.equal(boundsRequests, 2)
})

test("flight mask uses the just-loaded range, including on first load", async () => {
  const applied = []
  const empty = { type: "FeatureCollection", features: [] }
  const layers = {
    flights: { visible: true, update() {} },
    "points-mvt": {
      setFlightWindows: (windows) => applied.push(["points", windows]),
    },
    "tracks-mvt": {
      setFlightWindows: (windows) => applied.push(["tracks", windows]),
    },
  }
  const controller = {
    map: {},
    dataLoader: {
      fetchMapData: async (startDate, _endDate, options) => {
        const flightsGeoJSON = { windows: [[startDate, `${startDate}-end`]] }
        options.onLayerData("flights", flightsGeoJSON)
        return {
          visits: [],
          visitsGeoJSON: empty,
          areasGeoJSON: empty,
          placesGeoJSON: empty,
          flightsGeoJSON,
          backgroundReady: Promise.resolve(),
        }
      },
    },
    layerManager: {
      updatePointTileRange() {},
      getLayer: (name) => layers[name],
    },
    filterManager: { setAllVisits() {} },
    showProgress() {},
    hideProgress() {},
    hasProgressBadgeTarget: false,
  }
  const manager = new MapDataManager(controller)
  manager._setupLayers = async () => {}

  await manager.loadMapData("2026-06-01", "2026-06-30", {
    showLoading: false,
    fitBounds: false,
  })
  assert.deepEqual(applied.at(-1), [
    "tracks",
    [["2026-06-01", "2026-06-01-end"]],
  ])

  await manager.loadMapData("2026-07-01", "2026-07-31", {
    showLoading: false,
    fitBounds: false,
  })
  assert.deepEqual(applied.at(-1), [
    "tracks",
    [["2026-07-01", "2026-07-01-end"]],
  ])
})

test("late history bounds cannot refit an older date range", async () => {
  const fits = []
  const empty = { type: "FeatureCollection", features: [] }
  let resolveOlder
  const controller = {
    map: {
      getContainer: () => ({ getBoundingClientRect: () => null }),
      fitBounds: (bounds) => fits.push(bounds.coordinates),
    },
    api: {
      fetchHistoryBounds: ({ start_at }) =>
        start_at === "2026-06-01"
          ? new Promise((resolve) => {
              resolveOlder = resolve
            })
          : Promise.resolve({
              min_lng: 13,
              min_lat: 52,
              max_lng: 14,
              max_lat: 53,
            }),
    },
    dataLoader: {
      fetchMapData: async () => ({
        visits: [],
        visitsGeoJSON: empty,
        areasGeoJSON: empty,
        placesGeoJSON: empty,
        backgroundReady: Promise.resolve(),
      }),
    },
    layerManager: { updatePointTileRange() {}, getLayer: () => null },
    filterManager: { setAllVisits() {} },
    showProgress() {},
    hideProgress() {},
    hasProgressBadgeTarget: false,
  }
  const manager = new MapDataManager(controller)
  manager._setupLayers = async () => {}

  const older = manager.loadMapData("2026-06-01", "2026-06-30", {
    showLoading: false,
  })
  await manager.loadMapData("2026-07-01", "2026-07-31", {
    showLoading: false,
  })
  resolveOlder({ min_lng: -74, min_lat: 40, max_lng: -73, max_lat: 41 })
  await older

  assert.deepEqual(fits, [
    [
      [13, 52],
      [14, 53],
    ],
  ])
})

test("late range callbacks cannot replace the current layers, replay data or progress", async () => {
  const requests = []
  const updates = []
  const progress = []
  const visits = []
  const windows = []
  const layers = {
    visits: { update: (value) => updates.push(["visits", value]) },
    photos: { update: (value) => updates.push(["photos", value]) },
    flights: {
      visible: true,
      update: (value) => updates.push(["flights", value]),
    },
    "points-mvt": { setFlightWindows: (value) => windows.push(value) },
    "tracks-mvt": { setFlightWindows: (value) => windows.push(value) },
  }
  const controller = {
    map: {},
    dataLoader: {
      fetchMapData: (_startDate, _endDate, callbacks) =>
        new Promise((resolve) => requests.push({ callbacks, resolve })),
    },
    layerManager: {
      updatePointTileRange() {},
      getLayer: (name) => layers[name],
    },
    filterManager: { setAllVisits: (value) => visits.push(value) },
    updateLoadingCounts: (value) => progress.push(value),
    showProgress() {},
    hideProgress() {},
    hasProgressBadgeTarget: false,
  }
  const manager = new MapDataManager(controller)
  manager._setupLayers = async () => {}
  const empty = { type: "FeatureCollection", features: [] }
  const resultFor = (label) => ({
    visits: [label],
    visitsGeoJSON: empty,
    areasGeoJSON: empty,
    placesGeoJSON: empty,
    flightsGeoJSON: { windows: [label] },
    backgroundReady: Promise.resolve(),
  })

  const older = manager.loadMapData("2026-06-01", "2026-06-30", {
    fitBounds: false,
  })
  await new Promise(setImmediate)
  const newer = manager.loadMapData("2026-07-01", "2026-07-31", {
    fitBounds: false,
  })
  await new Promise(setImmediate)
  assert.equal(requests.length, 2)

  requests[1].callbacks.onLayerData("flights", { windows: ["new"] })
  requests[1].callbacks.onUpdate({ counts: { visits: 1 } })
  requests[1].resolve(resultFor("new"))
  await newer
  requests[0].callbacks.onLayerData("flights", { windows: ["old"] })
  requests[0].callbacks.onPhotosLoaded({ photos: ["old"] })
  requests[0].callbacks.onUpdate({ counts: { visits: 2 } })
  requests[0].resolve(resultFor("old"))
  assert.equal(await older, null)

  assert.deepEqual(visits, [["new"]])
  assert.deepEqual(manager.lastLoadedData.visits, ["new"])
  assert.deepEqual(progress, [{ counts: { visits: 1 } }])
  assert.deepEqual(windows.at(-1), ["new"])
  assert.equal(
    updates.some(([, value]) => value?.windows?.[0] === "old"),
    false,
  )
  assert.equal(
    updates.some(([, value]) => value?.photos?.[0] === "old"),
    false,
  )
})
