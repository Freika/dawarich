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

test("a trip provider satisfies the same contract without a map", async () => {
  // Trip pages hand the studio their geojson up front, so there is nothing to
  // load — but the studio calls this on whatever provider it was given.
  const provider = new TripProvider({
    geojson: { type: "FeatureCollection", features: [] },
    points: [],
  })

  await provider.ensureTrackLoaded()
})
