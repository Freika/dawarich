import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// MapPageProvider reaches the live map through document.getElementById; the
// module itself imports nothing, so a minimal DOM shim is all Node needs.
globalThis.document = { getElementById: () => ({}) }

const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/data/providers.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { MapPageProvider, TripProvider } = await import(moduleUrl)

// Mirrors the real controller: ensurePointsLoaded() is what builds the routes
// GeoJSON and fills the routes layer, so the track is only readable after it.
function fakeMapPage() {
  const controller = {
    loads: 0,
    mapDataManager: {
      async ensurePointsLoaded() {
        controller.loads += 1
      },
    },
    _getLoadedPoints: () => [{ latitude: "51.3402", longitude: "12.3712" }],
  }
  const application = {
    getControllerForElementAndIdentifier: () => controller,
  }
  return { controller, provider: new MapPageProvider({ application }) }
}

test("forces the map's lazy point load so the track becomes readable", async () => {
  const { controller, provider } = fakeMapPage()

  await provider.ensureTrackLoaded()

  assert.equal(controller.loads, 1)
})

test("points still resolve through the same lazy load", async () => {
  const { controller, provider } = fakeMapPage()

  const points = await provider.points()

  assert.equal(controller.loads, 1)
  assert.equal(points.length, 1)
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
