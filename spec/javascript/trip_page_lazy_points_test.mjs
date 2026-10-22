import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const stubs = `
  class Controller {}
  const translate = (key) => key
  const maplibregl = {}
  const env = globalThis.__tripEnv
  const MapInitializer = { initialize: (...args) => env.initialize(...args) }
  class TripRoutesTileLayer {
    constructor(map, options) {
      this.options = options
      this.excluded = []
      env.tileLayers.push(this)
    }
    setExcludedWindows(windows) { this.excluded = windows }
    setupInteractions() {}
    getDayColor() { return "#000" }
    getDayKeys() { return this.options.dayKeys }
    getFullBounds() { return this.options.fullBounds }
    getDayBounds() { return null }
    selectDay() {}
    selectAllDays() {}
    remove() {}
  }
  class FlightsLayer {
    constructor() { this.visible = true }
    add(data) { this.data = data }
    hide() { this.visible = false }
    show() { this.visible = true }
    update(data) { this.data = data }
    remove() {}
  }
  class PhotosLayer {}
  class TripPlanLayer {}
  class ReplayPanel {}
  class ReplayManager {
    setPoints(points) { this.points = points }
    get availableDays() { return this.points.length ? ["2026-01-01"] : [] }
    getPointsForDay() { return this.points }
  }
  class ApiClient {
    fetchAllPoints(params) { return env.fetchAllPoints(params) }
    fetchFlights() { return env.fetchFlights() }
  }
  const pointsFromDevice = (points) => points
  const featureToPhoto = (feature) => feature
  const flightWindows = (geojson) => geojson.features.map((f) => f.window)
  const maskLines = (geojson) => geojson
  const buildDayRouteCollections = (pointsByDay) =>
    Object.keys(pointsByDay).map((day) => ({ type: "FeatureCollection", day, features: [] }))
  const buildTripGeojson = ({ dayRouteCollections }) => ({
    type: "FeatureCollection",
    features: dayRouteCollections.flatMap((c) => c.features),
    days: dayRouteCollections.map((c) => c.day),
  })
  class TripProvider { constructor(options) { this.options = options } }
  const Flash = { show: (...args) => env.flashes.push(args) }
`
globalThis.__tripEnv = {}
const { default: TripController } = await import(
  moduleUrl(
    `${stubs}\n${stripImports(await read("controllers/trip_maplibre_controller.js"))}`,
  )
)

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

function setup(t) {
  const env = Object.assign(globalThis.__tripEnv, {
    tileLayers: [],
    flashes: [],
    initializeCalls: [],
    fetches: [],
    events: [],
    fetchAllPoints: (params) => {
      env.fetches.push(params)
      return Promise.resolve({ points: [{ timestamp: 1 }, { timestamp: 2 }] })
    },
    fetchFlights: () =>
      Promise.resolve({
        type: "FeatureCollection",
        features: [
          { window: [1767225600, 1767229200] },
          { window: [1600000000, 1600003600] },
        ],
      }),
    initialize: async (...args) => {
      env.initializeCalls.push(args)
      return {
        on: (event, callback) => event === "load" && env.loads.push(callback),
        fitBounds() {},
        remove() {},
      }
    },
    loads: [],
  })
  const originals = ["window", "document"].map((name) => [
    name,
    Object.getOwnPropertyDescriptor(globalThis, name),
  ])
  t.after(() => {
    for (const [name, original] of originals) {
      if (original) Object.defineProperty(globalThis, name, original)
      else delete globalThis[name]
    }
  })
  globalThis.window = { addEventListener() {}, removeEventListener() {} }
  globalThis.document = {
    dispatchEvent: (event) => env.events.push(event.type),
  }

  const controller = new TripController()
  const button = () => ({
    disabled: false,
    setAttribute() {},
    removeAttribute() {},
  })
  Object.assign(controller, {
    element: { isConnected: true },
    hasMapTarget: true,
    mapTarget: {},
    hasPathPendingTarget: false,
    hasDaysAccordionTarget: false,
    hasReplayPanelTarget: false,
    hasPosterBtnTarget: true,
    posterBtnTarget: button(),
    hasVideoBtnTarget: true,
    videoBtnTarget: button(),
    hasReplayToggleBtnTarget: true,
    replayToggleBtnTarget: button(),
    flightsToggleBtnTarget: { classList: { add() {}, remove() {} } },
    apiKeyValue: "secret-key",
    timezoneValue: "UTC",
    startedAtValue: "2026-01-01T00:00:00Z",
    endedAtValue: "2026-01-02T00:00:00Z",
    tilesUrlValue: "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?v=1",
    dayKeysValue: ["2026-01-01"],
    dayBoundsValue: {},
    dayEndpointsValue: {},
    fullBoundsValue: [
      [13, 52],
      [14, 53],
    ],
    deviceWindowsValue: [],
  })
  return { controller, env }
}

async function connected(t) {
  const context = setup(t)
  await context.controller.connect()
  for (const load of context.env.loads) await load()
  return context
}

test("draws the trip from tiles on load without downloading points", async (t) => {
  const { env } = await connected(t)

  assert.equal(env.fetches.length, 0)
  assert.equal(env.initializeCalls[0][2], "secret-key")
  assert.equal(env.tileLayers.length, 1)
  assert.equal(
    env.tileLayers[0].options.tilesUrl,
    "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?v=1",
  )
  assert.deepEqual(env.tileLayers[0].options.dayKeys, ["2026-01-01"])
})

test("concurrent studio opens share one points download", async (t) => {
  const { controller, env } = await connected(t)

  await Promise.all([
    controller.openPosterStudio(),
    controller.openVideoStudio(),
  ])

  assert.equal(env.fetches.length, 1)
  assert.deepEqual(env.events, ["poster-studio:open", "video-studio:open"])
  assert.deepEqual(controller.posterProvider().options.geojson.days, [
    "2026-01-01",
  ])
})

test("a failed download is reported and retried on the next open", async (t) => {
  const { controller, env } = await connected(t)
  const succeed = env.fetchAllPoints
  env.fetchAllPoints = (params) => {
    env.fetches.push(params)
    return Promise.reject(new Error("offline"))
  }
  t.mock.method(console, "error", () => {})

  await controller.openPosterStudio()
  assert.deepEqual(env.events, [])
  assert.equal(env.flashes[0][0], "error")
  assert.equal(controller.posterBtnTarget.disabled, false)

  env.fetchAllPoints = succeed
  await controller.openPosterStudio()

  assert.equal(env.fetches.length, 2)
  assert.deepEqual(env.events, ["poster-studio:open"])
})

test("leaving the page before points arrive opens no studio", async (t) => {
  const { controller, env } = await connected(t)
  const pending = deferred()
  env.fetchAllPoints = (params) => {
    env.fetches.push(params)
    return pending.promise
  }

  const opening = controller.openPosterStudio()
  assert.equal(controller.posterBtnTarget.disabled, true)
  controller.disconnect()
  controller.element.isConnected = false
  pending.resolve({ points: [{ timestamp: 1 }] })
  await opening

  assert.deepEqual(env.events, [])
})

test("flights ask the tiles to leave out the flight windows", async (t) => {
  const { controller, env } = await connected(t)

  await controller.toggleFlights()
  assert.deepEqual(env.tileLayers[0].excluded, [[1767225600, 1767229200]])

  await controller.toggleFlights()
  assert.deepEqual(env.tileLayers[0].excluded, [])
})

test("the map target connecting before the controller builds one map", async (t) => {
  const { controller, env } = setup(t)

  const targetConnected = controller.mapTargetConnected()
  await controller.connect()
  await targetConnected

  assert.equal(env.initializeCalls.length, 1)
})

test("loading points leaves buttons the server disabled switched off", async (t) => {
  const { controller } = await connected(t)
  controller.posterBtnTarget.disabled = true

  await controller.ensurePoints()

  assert.equal(controller.posterBtnTarget.disabled, true)
  assert.equal(controller.replayToggleBtnTarget.disabled, false)
})
