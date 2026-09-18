import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

globalThis.document = { getElementById: () => ({}) }

const segmenterSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/route_segmenter.js",
    import.meta.url,
  ),
  "utf8",
)
const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/data/providers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(segmenterSource.replace(/^export /gm, "") + withoutImports).toString("base64")}`
const { MapPageProvider, TripProvider } = await import(moduleUrl)

// Mirrors the real controller: poster/video generation is an explicit bounded
// consumer which loads exact points and canonical tracks on demand.
function fakeMapPage() {
  const controller = {
    pointLoads: 0,
    trackLoads: 0,
    mapDataManager: {
      async ensurePointsLoaded() {
        controller.pointLoads += 1
      },
    },
    api: {
      async fetchTracks() {
        controller.trackLoads += 1
        return { type: "FeatureCollection", features: [] }
      },
    },
    _getLoadedPoints: () => [{ latitude: "51.3402", longitude: "12.3712" }],
  }
  const application = {
    getControllerForElementAndIdentifier: () => controller,
  }
  return { controller, provider: new MapPageProvider({ application }) }
}

test("loads exact points and canonical tracks for the studio", async () => {
  const { controller, provider } = fakeMapPage()

  await provider.ensureTrackLoaded()

  assert.equal(controller.pointLoads, 1)
  assert.equal(controller.trackLoads, 1)
})

test("points still resolve through the same lazy load", async () => {
  const { controller, provider } = fakeMapPage()

  const points = await provider.points()

  assert.equal(controller.pointLoads, 1)
  assert.equal(controller.trackLoads, 1)
  assert.equal(points.length, 1)
})

test("import-scoped studio geometry uses only imported points", async () => {
  const { controller, provider } = fakeMapPage()
  controller.api.importId = 42
  controller._getLoadedPoints = () => [
    { latitude: 52.5, longitude: 13.4, timestamp: 1 },
    { latitude: 52.6, longitude: 13.5, timestamp: 2 },
  ]

  await provider.ensureTrackLoaded()

  assert.equal(controller.pointLoads, 1)
  assert.equal(controller.trackLoads, 0)
  assert.deepEqual(provider.trackGeojson().features[0].geometry.coordinates, [
    [13.4, 52.5],
    [13.5, 52.6],
  ])
})

test("date changes wait for the map reload promise", async (t) => {
  const { controller, provider } = fakeMapPage()
  controller.timezoneValue = "Europe/Berlin"
  let finishReload
  const reload = new Promise((resolve) => {
    finishReload = resolve
  })
  let pushedUrl = null
  const originalDocument = globalThis.document
  const originalWindow = globalThis.window
  const originalCustomEvent = globalThis.CustomEvent
  globalThis.document = {
    getElementById: () => ({}),
    dispatchEvent: (event) => event.detail.waitUntil(reload),
  }
  globalThis.window = {
    location: { search: "?panel=timeline" },
    history: {
      pushState: (_state, _title, url) => {
        pushedUrl = url
      },
    },
  }
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = type
      this.detail = options.detail
    }
  }
  t.after(() => {
    globalThis.document = originalDocument
    globalThis.window = originalWindow
    globalThis.CustomEvent = originalCustomEvent
  })

  let settled = false
  const pending = provider
    .applyDates("2026-07-11T14:30+02:00", "2026-07-11T18:45+02:00")
    .then(() => {
      settled = true
    })
  await Promise.resolve()

  assert.equal(settled, false)
  assert.equal(provider.timeZone(), "Europe/Berlin")
  assert.match(pushedUrl, /panel=timeline/)
  finishReload()
  await pending
  assert.equal(settled, true)
})

test("date changes fail when no map listener accepts the reload", async (t) => {
  const { provider } = fakeMapPage()
  const originalDocument = globalThis.document
  const originalWindow = globalThis.window
  const originalCustomEvent = globalThis.CustomEvent
  globalThis.document = {
    getElementById: () => ({}),
    dispatchEvent: () => {},
  }
  globalThis.window = {
    location: { search: "" },
    history: { pushState: () => {} },
  }
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = type
      this.detail = options.detail
    }
  }
  t.after(() => {
    globalThis.document = originalDocument
    globalThis.window = originalWindow
    globalThis.CustomEvent = originalCustomEvent
  })

  await assert.rejects(
    provider.applyDates("2026-07-11T14:30", "2026-07-11T18:45"),
    /unavailable/,
  )
})

test("a trip provider satisfies the same contract without a map", async () => {
  // Trip pages hand the studio their geojson up front, so there is nothing to
  // load — but the studio calls this on whatever provider it was given.
  const provider = new TripProvider({
    geojson: { type: "FeatureCollection", features: [] },
    points: [],
  })

  await provider.ensureTrackLoaded()
})
