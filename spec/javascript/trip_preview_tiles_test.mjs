import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const env = { initializeCalls: [], boundsRequests: [], maps: [] }
globalThis.__previewEnv = env

const fakeMap = () => {
  const map = {
    sources: {},
    layers: {},
    fits: [],
    handlers: {},
    ...Object.fromEntries(
      [
        "dragPan",
        "scrollZoom",
        "boxZoom",
        "dragRotate",
        "doubleClickZoom",
        "touchZoomRotate",
        "keyboard",
      ].map((name) => [name, { disable() {} }]),
    ),
    on(event, callback) {
      this.handlers[event] = callback
    },
    addSource(id, source) {
      this.sources[id] = source
    },
    getSource(id) {
      return this.sources[id]
    },
    removeSource(id) {
      delete this.sources[id]
    },
    addLayer(layer) {
      this.layers[layer.id] = layer
    },
    getLayer(id) {
      return this.layers[id]
    },
    removeLayer(id) {
      delete this.layers[id]
    },
    fitBounds(bounds) {
      this.fits.push(bounds)
    },
    remove() {},
  }
  env.maps.push(map)
  return map
}

const { default: PreviewController } = await import(
  moduleUrl(`
    class Controller {}
    const env = globalThis.__previewEnv
    const maplibregl = {}
    const MapInitializer = {
      initialize: async (...args) => {
        env.initializeCalls.push(args)
        return env.makeMap()
      },
    }
    class TripPlanLayer {}
    const RouteSegmenter = {}
    class ApiClient {
      constructor(apiKey) { this.apiKey = apiKey }
      fetchHistoryBounds(params) {
        env.boundsRequests.push({ apiKey: this.apiKey, ...params })
        return Promise.resolve(env.bounds)
      }
    }
    ${stripImports(await read("controllers/trip_maplibre_preview_controller.js"))}
  `)
)
env.makeMap = fakeMap

const { default: DatetimeController } = await import(
  moduleUrl(`
    class BaseController {}
    const translate = (key) => key
    ${stripImports(await read("controllers/datetime_controller.js"))}
  `)
)

function element() {
  const listeners = {}
  return {
    listeners,
    addEventListener(type, handler) {
      listeners[type] = handler
    },
    removeEventListener(type) {
      delete listeners[type]
    },
  }
}

async function preview(t, values = {}) {
  const originalWindow = globalThis.window
  t.after(() => {
    globalThis.window = originalWindow
  })
  globalThis.window = { addEventListener() {}, removeEventListener() {} }

  const controller = new PreviewController()
  Object.assign(controller, {
    element: element(),
    mapStyleValue: "light",
    interactiveValue: true,
    hasLinesUrlValue: false,
    hasLinesValue: false,
    hasPlanValue: false,
    apiKeyValue: "secret-key",
    tilesUrlValue: "",
    boundsValue: [],
    ...values,
  })
  await controller.connect()
  const map = env.maps.at(-1)
  map.handlers.load()
  return { controller, map }
}

const lineLayer = (map) => Object.values(map.layers)[0]
const lineSource = (map) => Object.values(map.sources)[0]

test("a trip card draws its route from the trip tiles", async (t) => {
  const { map } = await preview(t, {
    interactiveValue: false,
    tilesUrlValue: "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?v=1",
    boundsValue: [
      [13.4, 52.5],
      [13.5, 52.55],
    ],
  })

  assert.equal(env.initializeCalls.at(-1)[2], "secret-key")
  assert.equal(lineSource(map).type, "vector")
  assert.deepEqual(lineSource(map).tiles, [
    "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?v=1",
  ])
  assert.equal(lineLayer(map)["source-layer"], "trip_routes")
  assert.deepEqual(map.fits.at(-1), [
    [13.4, 52.5],
    [13.5, 52.55],
  ])
})

test("a new date range shows the tracks of that range", async (t) => {
  const { controller, map } = await preview(t)
  env.bounds = { min_lng: 2, min_lat: 48, max_lng: 3, max_lat: 49 }

  await controller.element.listeners["trip-range-updated"]({
    detail: { startAt: "2026-01-01T10:00", endAt: "2026-01-02T10:00" },
  })

  assert.deepEqual(env.boundsRequests.at(-1), {
    apiKey: "secret-key",
    start_at: "2026-01-01T10:00",
    end_at: "2026-01-02T10:00",
  })
  const [path, query] = lineSource(map).tiles[0].split("?")
  const params = new URLSearchParams(query)
  assert.equal(path, "/api/v1/tiles/tracks/{z}/{x}/{y}.mvt")
  assert.equal(params.get("start_at"), "2026-01-01T10:00")
  assert.equal(params.get("end_at"), "2026-01-02T10:00")
  assert.equal(lineLayer(map)["source-layer"], "tracks")
  assert.deepEqual(map.fits.at(-1), [
    [2, 48],
    [3, 49],
  ])
})

test("a range chosen before the map loads is drawn once it loads", async (t) => {
  const originalWindow = globalThis.window
  t.after(() => {
    globalThis.window = originalWindow
  })
  globalThis.window = { addEventListener() {}, removeEventListener() {} }
  env.bounds = { min_lng: 2, min_lat: 48, max_lng: 3, max_lat: 49 }
  const controller = new PreviewController()
  Object.assign(controller, {
    element: element(),
    mapStyleValue: "light",
    interactiveValue: true,
    hasLinesUrlValue: false,
    hasLinesValue: false,
    hasPlanValue: false,
    apiKeyValue: "secret-key",
    tilesUrlValue: "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?v=1",
    boundsValue: [
      [13.4, 52.5],
      [13.5, 52.55],
    ],
  })
  await controller.connect()
  const map = env.maps.at(-1)

  await controller.element.listeners["trip-range-updated"]({
    detail: { startAt: "2026-01-01T10:00", endAt: "2026-01-02T10:00" },
  })
  assert.deepEqual(map.sources, {})

  map.handlers.load()

  assert.equal(lineLayer(map)["source-layer"], "tracks")
})

test("changing the form dates downloads no points", async (t) => {
  const requests = []
  const dispatched = []
  const originals = ["fetch", "document"].map((name) => [
    name,
    globalThis[name],
  ])
  t.after(() => {
    for (const [name, value] of originals) globalThis[name] = value
  })
  globalThis.fetch = async (...args) => {
    requests.push(args)
    return { ok: true, json: async () => [], headers: { get: () => "1" } }
  }
  globalThis.document = {
    querySelector: () => ({ dispatchEvent: (event) => dispatched.push(event) }),
  }
  t.mock.timers.enable({ apis: ["setTimeout"] })

  const controller = new DatetimeController()
  Object.assign(controller, {
    startedAtTarget: { value: "2026-01-01T10:00", setCustomValidity() {} },
    endedAtTarget: { value: "2026-01-02T10:00", setCustomValidity() {} },
  })
  controller.updateCoordinates()
  t.mock.timers.tick(500)
  await new Promise((resolve) => setImmediate(resolve))

  assert.deepEqual(requests, [])
  assert.equal(dispatched[0].type, "trip-range-updated")
  assert.deepEqual(dispatched[0].detail, {
    startAt: "2026-01-01T10:00",
    endAt: "2026-01-02T10:00",
  })
})
