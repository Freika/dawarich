import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/data/providers.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { buildTripGeojson, MapPageProvider, TripProvider } = await import(
  moduleUrl
)

const lineString = (coordinates) => ({
  type: "Feature",
  properties: {},
  geometry: { type: "LineString", coordinates },
})

test("TripProvider returns the snapshot it was built with", () => {
  const geojson = {
    type: "FeatureCollection",
    features: [
      lineString([
        [13.4, 52.5],
        [13.5, 52.6],
      ]),
    ],
  }
  const provider = new TripProvider({
    geojson,
    startAt: "2026-05-01T00:00:00Z",
    endAt: "2026-05-09T23:59:59Z",
    title: "Berlin Trip",
  })
  assert.equal(provider.trackGeojson(), geojson)
  assert.deepEqual(provider.dateRange(), {
    startAt: "2026-05-01T00:00:00Z",
    endAt: "2026-05-09T23:59:59Z",
  })
  assert.equal(provider.defaultTitle(), "Berlin Trip")
  assert.equal(provider.trackSource(), "routes")
  assert.equal(provider.supportsDateNavigation, false)
  assert.equal(provider.fallbackBounds(), null)
})

test("TripProvider defaults to an empty collection and blank title", () => {
  const provider = new TripProvider({ startAt: "a", endAt: "b" })
  assert.deepEqual(provider.trackGeojson(), {
    type: "FeatureCollection",
    features: [],
  })
  assert.equal(provider.defaultTitle(), "")
})

test("MapPageProvider reads layers and dates from the maps controller", (t) => {
  const layers = {
    routes: { data: { type: "FeatureCollection", features: [] } },
    tracks: {
      data: { type: "FeatureCollection", features: [lineString([[0, 0]])] },
    },
  }
  const fakeController = {
    layerManager: { getLayer: (name) => layers[name] },
    startDateValue: "2026-01-01T00:00",
    endDateValue: "2026-01-31T23:59",
  }
  const originalDocument = globalThis.document
  globalThis.document = { getElementById: () => ({}) }
  t.after(() => {
    globalThis.document = originalDocument
  })
  const provider = new MapPageProvider({
    application: { getControllerForElementAndIdentifier: () => fakeController },
  })

  assert.equal(provider.trackSource(), "tracks")
  assert.equal(provider.trackGeojson(), layers.tracks.data)
  assert.deepEqual(provider.dateRange(), {
    startAt: "2026-01-01T00:00",
    endAt: "2026-01-31T23:59",
  })
  assert.equal(provider.defaultTitle(), "")
  assert.equal(provider.supportsDateNavigation, true)

  layers.routes.data.features.push(lineString([[1, 1]]))
  assert.equal(provider.trackSource(), "routes")
})

test("buildTripGeojson merges day-route collections when present", () => {
  const day1 = { features: [lineString([[13.4, 52.5]])] }
  const day2 = { features: [lineString([[13.5, 52.6]])] }
  const geojson = buildTripGeojson({
    dayRouteCollections: [day1, day2],
    pathData: JSON.stringify([
      [1, 1],
      [2, 2],
    ]),
  })
  assert.equal(geojson.features.length, 2)
  assert.deepEqual(geojson.features[0], day1.features[0])
})

test("buildTripGeojson falls back to the path overview line", () => {
  const geojson = buildTripGeojson({
    dayRouteCollections: [{ features: [] }],
    pathData: JSON.stringify([
      [13.4, 52.5],
      [13.5, 52.6],
    ]),
  })
  assert.equal(geojson.features.length, 1)
  assert.equal(geojson.features[0].geometry.type, "LineString")
  assert.deepEqual(geojson.features[0].geometry.coordinates, [
    [13.4, 52.5],
    [13.5, 52.6],
  ])
})

test("buildTripGeojson yields an empty collection for degenerate input", () => {
  for (const pathData of [null, "not json", JSON.stringify([[1, 1]])]) {
    const geojson = buildTripGeojson({ dayRouteCollections: [], pathData })
    assert.deepEqual(geojson, { type: "FeatureCollection", features: [] })
  }
})

test("MapPageProvider degrades to empty data without a maps controller", (t) => {
  const originalDocument = globalThis.document
  globalThis.document = { getElementById: () => null }
  t.after(() => {
    globalThis.document = originalDocument
  })
  const provider = new MapPageProvider({
    application: { getControllerForElementAndIdentifier: () => null },
  })
  assert.deepEqual(provider.trackGeojson(), {
    type: "FeatureCollection",
    features: [],
  })
  assert.deepEqual(provider.dateRange(), { startAt: "", endAt: "" })
  assert.equal(provider.fallbackBounds(), null)
})
