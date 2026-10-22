import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const env = { tileLayers: [], panels: [], maps: [] }
globalThis.__sharedEnv = env

const { default: SharedTripController } = await import(
  moduleUrl(`
    class Controller {}
    const env = globalThis.__sharedEnv
    const getMapStyle = async () => ({})
    const maplibregl = {
      Map: class {
        constructor() { this.handlers = {}; this.fits = []; env.maps.push(this) }
        addControl() {}
        on(event, callback) { this.handlers[event] = callback }
        fitBounds(bounds) { this.fits.push(bounds) }
        remove() {}
      },
      NavigationControl: class {},
    }
    class TripRoutesTileLayer {
      constructor(map, options) { this.options = options; env.tileLayers.push(this) }
      getDayColor(day) { return this.options.dayKeys.includes(day) ? "#000" : null }
      getFullBounds() { return this.options.fullBounds }
      setupInteractions() {}
      remove() {}
    }
    class ReplayPanel {
      constructor(options) { this.options = options; env.panels.push(this) }
      async toggle() { this.points = await this.options.loadPoints() }
      destroy() {}
    }
    ${stripImports(await read("controllers/shared_trip_map_controller.js"))}
  `)
)

function setup(t) {
  const requests = []
  const originalFetch = globalThis.fetch
  t.after(() => {
    globalThis.fetch = originalFetch
  })
  globalThis.fetch = async (url) => {
    requests.push(url)
    return { ok: true, json: async () => [[13.4, 52.5, 1767261600]] }
  }

  const controller = new SharedTripController()
  Object.assign(controller, {
    element: { querySelectorAll: () => [] },
    hasMapTarget: false,
    linkIdValue: "abc",
    byDayValue: true,
    showPhotosValue: false,
    timezoneValue: "UTC",
    tilesUrlValue: "/api/v1/shared/abc/tiles/{z}/{x}/{y}.mvt",
    dayKeysValue: ["2026-01-01"],
    dayBoundsValue: {},
    dayEndpointsValue: {},
    fullBoundsValue: [
      [13, 52],
      [14, 53],
    ],
  })
  return { controller, requests }
}

async function opened(t) {
  const context = setup(t)
  context.controller.connect()
  await new Promise((resolve) => setImmediate(resolve))
  env.maps.at(-1).handlers.load()
  return context
}

test("a shared trip draws its routes from the shared tiles without points", async (t) => {
  const { requests } = await opened(t)
  const layer = env.tileLayers.at(-1)

  assert.deepEqual(requests, [])
  assert.equal(
    layer.options.tilesUrl,
    "/api/v1/shared/abc/tiles/{z}/{x}/{y}.mvt",
  )
  assert.deepEqual(layer.options.dayKeys, ["2026-01-01"])
  assert.deepEqual(env.maps.at(-1).fits.at(-1), [
    [13, 52],
    [14, 53],
  ])
})

test("replay downloads the shared points once, when opened", async (t) => {
  const { controller, requests } = await opened(t)

  await controller.toggleReplay()
  await controller.toggleReplay()

  assert.deepEqual(requests, ["/api/v1/shared/abc/points"])
  assert.deepEqual(env.panels.at(-1).points, [
    { longitude: 13.4, latitude: 52.5, timestamp: 1767261600 },
  ])
})

test("leaving the page before replay points arrive starts no replay", async (t) => {
  const { controller } = await opened(t)

  const toggling = controller.toggleReplay()
  controller.disconnect()
  await toggling

  assert.deepEqual(env.panels.at(-1).points, [])
})
