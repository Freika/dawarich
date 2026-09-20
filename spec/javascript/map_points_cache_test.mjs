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
    const Toast = { error() {}, success() {} }
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
