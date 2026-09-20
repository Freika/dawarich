import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadModule(path) {
  const source = (
    await readFile(
      new URL(`../../app/javascript/${path}`, import.meta.url),
      "utf8",
    )
  ).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const stubs = `
    class Controller {}
    const translate = (key) => key
    const Toast = { error() {}, success() {}, info() {} }
    const pointMatchesActiveDateRange = () => true
  `
  return import(
    `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
  )
}

const { MapDataManager } = await loadModule(
  "controllers/maps/maplibre/map_data_manager.js",
)
const { default: MapsController } = await loadModule(
  "controllers/maps/maplibre_controller.js",
)
const { default: RealtimeController } = await loadModule(
  "controllers/maps/maplibre_realtime_controller.js",
)

globalThis.document = { dispatchEvent() {} }
globalThis.CustomEvent = class {
  constructor(type, options) {
    this.type = type
    this.detail = options.detail
  }
}
globalThis.confirm = () => true

function mapController(fetchPointsData) {
  const controller = new MapsController()
  Object.assign(controller, {
    dataLoader: { fetchPointsData },
    layerManager: { getLayer: () => null },
    showProgress() {},
    hideProgress() {},
    updateLoadingCounts() {},
    closeInfo() {},
  })
  controller.mapDataManager = new MapDataManager(controller)
  return controller
}

function result(longitude = 0) {
  return {
    points: [{ id: 7, longitude, latitude: 0 }],
    pointsGeoJSON: { type: "FeatureCollection", features: [] },
  }
}

test("remote point moves refresh previously loaded exact points", async () => {
  let longitude = 0
  const maps = mapController(async () => result(longitude))
  const realtime = new RealtimeController()
  Object.defineProperty(realtime, "mapsV2Controller", { value: maps })
  await maps.mapDataManager.ensurePointsLoaded()

  longitude = 1
  realtime.handleMapEdit({
    type: "point_moved",
    data: { point: { id: 7, longitude, latitude: 0 } },
  })
  await maps.mapDataManager.ensurePointsLoaded()

  assert.equal(maps.mapDataManager.lastLoadedData.points[0].longitude, 1)
})

test("deleting a point removes it from the next exact-point load", async () => {
  let points = result().points
  const maps = mapController(async () => ({ ...result(), points }))
  maps.api = {
    deletePoint: async () => {
      points = []
    },
  }
  await maps.mapDataManager.ensurePointsLoaded()

  await maps.deletePoint(7)
  await maps.mapDataManager.ensurePointsLoaded()

  assert.deepEqual(maps.mapDataManager.lastLoadedData.points, [])
})

test("failed deletion retains loaded points", async () => {
  let requests = 0
  const maps = mapController(async () => {
    requests += 1
    return result()
  })
  maps.api = {
    deletePoint: async () => {
      throw new Error("offline")
    },
  }
  await maps.mapDataManager.ensurePointsLoaded()

  await maps.deletePoint(7)
  await maps.mapDataManager.ensurePointsLoaded()

  assert.equal(maps.mapDataManager.lastLoadedData.points[0].id, 7)
  assert.equal(requests, 1)
})

test("an edit during an exact-point load discards and refetches the old response", async () => {
  let resolveOld
  let requests = 0
  const maps = mapController(async () => {
    requests += 1
    if (requests === 1)
      return new Promise((resolve) => {
        resolveOld = resolve
      })
    return result(1)
  })
  const first = maps.mapDataManager.ensurePointsLoaded()
  const second = maps.mapDataManager.ensurePointsLoaded()
  maps.mapDataManager.invalidatePoints()
  resolveOld(result(0))

  await Promise.all([first, second])

  assert.equal(maps.mapDataManager.lastLoadedData.points[0].longitude, 1)
  assert.equal(requests, 2)
})

test("a pre-edit response cannot overwrite a newer completed load", async () => {
  let resolveOld
  let requests = 0
  const maps = mapController(async () => {
    requests += 1
    if (requests === 1)
      return new Promise((resolve) => {
        resolveOld = resolve
      })
    return result(1)
  })
  const first = maps.mapDataManager.ensurePointsLoaded()
  maps.mapDataManager.invalidatePoints()
  await maps.mapDataManager.ensurePointsLoaded()
  resolveOld(result(0))
  await first

  assert.equal(maps.mapDataManager.lastLoadedData.points[0].longitude, 1)
  assert.equal(requests, 2)
})

test("an invalidated failed points request clears its loading indicator", async () => {
  let rejectLoad
  let hidden = 0
  const maps = mapController(
    () =>
      new Promise((_resolve, reject) => {
        rejectLoad = reject
      }),
  )
  maps.hideProgress = () => {
    hidden += 1
  }
  const loading = maps.mapDataManager.ensurePointsLoaded()
  maps.mapDataManager.invalidatePoints()
  rejectLoad(new Error("offline"))

  await assert.rejects(loading, /offline/)
  assert.equal(hidden, 1)
})

function liveController(maps) {
  maps.realtimeDateRange = () => ({})
  const realtime = new RealtimeController()
  Object.defineProperty(realtime, "mapsV2Controller", { value: maps })
  realtime.updateRecentPoint = () => {}
  realtime.zoomToPoint = () => {}
  return realtime
}

test("live arrivals refresh cached points before the tile refresh timer", async () => {
  let points = result().points
  const maps = mapController(async () => ({ ...result(), points }))
  const realtime = liveController(maps)
  await maps.mapDataManager.ensurePointsLoaded()
  points = [...points, { id: 8, longitude: 1, latitude: 1 }]
  realtime.handleNewPoint([1, 1, 80, 0, 100, 0, 8, null])
  await maps.mapDataManager.ensurePointsLoaded()
  realtime.disconnect()

  assert.deepEqual(
    maps.mapDataManager.lastLoadedData.points.map((p) => p.id),
    [7, 8],
  )
})

test("a live arrival discards an older pending points response", async () => {
  let resolveOld
  let requests = 0
  const updated = [...result().points, { id: 8, longitude: 1, latitude: 1 }]
  const maps = mapController(async () => {
    requests += 1
    if (requests === 1)
      return new Promise((resolve) => {
        resolveOld = resolve
      })
    return { ...result(), points: updated }
  })
  const realtime = liveController(maps)
  const loading = maps.mapDataManager.ensurePointsLoaded()
  realtime.handleNewPoint([1, 1, 80, 0, 100, 0, 8, null])
  resolveOld(result())
  await loading
  realtime.disconnect()

  assert.deepEqual(
    maps.mapDataManager.lastLoadedData.points.map((p) => p.id),
    [7, 8],
  )
  assert.equal(requests, 2)
})

function pendingPoints() {
  const requests = []
  const maps = mapController(
    () => new Promise((resolve) => requests.push(resolve)),
  )
  return { maps, requests, manager: maps.mapDataManager }
}

const flushPoints = () => new Promise((resolve) => setImmediate(resolve))

test("continuous live arrivals share a bounded load and refresh on the next opening", async () => {
  const { maps, requests, manager } = pendingPoints()
  const realtime = liveController(maps)
  let settled = false
  const first = manager.ensurePointsLoaded().then(() => {
    settled = true
  })
  const second = manager.ensurePointsLoaded()
  realtime.handleNewPoint([1, 1, 80, 0, 100, 0, 8, null])
  const third = manager.ensurePointsLoaded()
  assert.equal(requests.length, 1)
  requests[0](result(0))
  await flushPoints()
  assert.equal(requests.length, 2)

  realtime.handleNewPoint([2, 1, 80, 0, 101, 0, 9, null])
  requests[1](result(1))
  await flushPoints()
  realtime.disconnect()

  assert.equal(settled, true)
  await Promise.all([first, second, third])
  assert.equal(requests.length, 2)
  assert.equal(manager.lastLoadedData.points[0].longitude, 1)

  const reopened = manager.ensurePointsLoaded()
  assert.equal(requests.length, 3)
  requests[2](result(2))
  await reopened
  assert.equal(manager.lastLoadedData.points[0].longitude, 2)
  await manager.ensurePointsLoaded()
  assert.equal(requests.length, 3)
})

test("hard mutations reject stale fallback snapshots without a retry limit", async () => {
  const { maps, requests, manager } = pendingPoints()
  const realtime = liveController(maps)
  let settled = false
  const loading = manager.ensurePointsLoaded().then(() => {
    settled = true
  })
  realtime.handleNewPoint([1, 1, 80, 0, 100, 0, 8, null])
  requests[0](result(0))
  await flushPoints()

  realtime.handleNewPoint([2, 1, 80, 0, 101, 0, 9, null])
  realtime.handleMapEdit({
    type: "point_moved",
    data: { point: { id: 7, longitude: 2, latitude: 0 } },
  })
  requests[1](result(1))
  await flushPoints()
  assert.equal(settled, false)
  assert.equal(manager.lastLoadedData?.points?.length ?? 0, 0)
  assert.equal(requests.length, 3)

  manager.invalidatePoints()
  requests[2](result(2))
  await flushPoints()
  assert.equal(settled, false)
  assert.equal(manager.lastLoadedData?.points?.length ?? 0, 0)
  assert.equal(requests.length, 4)

  requests[3](result(3))
  await loading
  realtime.disconnect()
  assert.equal(manager.lastLoadedData.points[0].longitude, 3)
})
