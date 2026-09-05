import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const providers = await read("poster_studio/data/providers.js")
const mask = await read("maps_maplibre/utils/flight_mask.js")
const arcs = await import(
  moduleUrl(await read("maps_maplibre/utils/flight_arcs.js"))
)
const controllerSource = (
  await read("controllers/trip_maplibre_controller.js")
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { default: TripController } = await import(
  moduleUrl(`class Controller {}\n${providers}\n${mask}\n${controllerSource}`)
)
const editorSource = (
  await read("controllers/poster_studio_editor_controller.js")
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
// Import constants stay inert until the editor connects; tests exercise the
// public geometry getter with actual providers, not a mocked method under test.
const previewSource = (await read("poster_studio/ui/preview.js")).replace(
  /^import[^\n]+\n/gm,
  "",
)
const frameSource = await read("poster_studio/render/frame_geometry.js")
const editorDependencies = `import { collectCoords } from "${moduleUrl(previewSource)}"; import { frameCovers } from "${moduleUrl(frameSource)}"; const translate = key => key;`
const { TripProvider } = await import(moduleUrl(providers))
const { default: Editor } = await import(
  moduleUrl(`class Controller {}\n${editorDependencies}\n${editorSource}`)
)
const fc = (features) => ({ type: "FeatureCollection", features })
const line = (id, startTime, endTime) => ({
  type: "Feature",
  properties: { id, startTime, endTime },
  geometry: {
    type: "LineString",
    coordinates: [
      [13, 52],
      [2, 49],
    ],
  },
})
const flight = {
  type: "Feature",
  properties: {
    id: "flight",
    departure_time: "2026-04-20T10:00:00Z",
    arrival_time: "2026-04-20T12:00:00Z",
  },
  geometry: {
    type: "LineString",
    coordinates: [
      [13.493, 52.351],
      [2.547, 49.009],
    ],
  },
}
const at = (hour) => Date.parse(`2026-04-20T${hour}:00:00Z`) / 1000
function setup(
  features = [
    line("ground", at("09"), at("10")),
    line("masked", at("10"), at("12")),
    line("partial", at("11"), at("13")),
  ],
) {
  const c = new TripController()
  Object.assign(c, {
    dayRoutesLayer: { dayRouteData: new Map([["2026-04-20", fc(features)]]) },
    pathDataValue: "[[0,0],[1,1]]",
    flightsActive: true,
    flightsGeoJSON: fc([flight]),
    flightsLayer: { visible: true, data: arcs.arcifyFlights(fc([flight])) },
    allPoints: [{ timestamp: at("11") }],
  })
  const editor = new Editor()
  editor.provider = c.posterProvider()
  return { c, editor, features }
}
const ids = (data) => data.features.map((f) => f.properties.id)

test("enabled Flights gives the poster arcs and the same whole-segment mask as the map", () => {
  const { c, editor } = setup()
  assert.deepEqual(ids(editor.trackGeojson), ["ground", "partial", "flight"])
  assert.deepEqual(
    editor.trackGeojson.features.at(-1).geometry,
    c.flightsLayer.data.features[0].geometry,
  )
  assert.ok(editor.trackGeojson.features.at(-1).geometry.coordinates.length > 2)
})
test("video retains the GPS geometry and timestamped points from the shared provider", async () => {
  const { c, editor } = setup()
  assert.deepEqual(ids(editor.provider.trackGeojson()), [
    "ground",
    "masked",
    "partial",
  ])
  assert.deepEqual(await editor.provider.points(), c.allPoints)
})
test("turning Flights off restores the GPS poster without mutating an open snapshot", () => {
  const { c, editor, features } = setup()
  const active = editor.trackGeojson
  c.flightsActive = false
  editor.provider = c.posterProvider()
  assert.deepEqual(
    ids(editor.trackGeojson),
    features.map((f) => f.properties.id),
  )
  assert.deepEqual(ids(active), ["ground", "partial", "flight"])
  assert.equal(
    c.dayRoutesLayer.dayRouteData.values().next().value.features,
    features,
  )
})
test("a hidden or not-yet-loaded flight layer does not mask the poster", () => {
  const { c, editor } = setup()
  c.flightsLayer.visible = false
  editor.provider = c.posterProvider()
  assert.deepEqual(ids(editor.trackGeojson), ["ground", "masked", "partial"])
  c.flightsLayer = null
  editor.provider = c.posterProvider()
  assert.deepEqual(ids(editor.trackGeojson), ["ground", "masked", "partial"])
})
test("a wholly masked GPS route stays hidden instead of returning through the path fallback", () => {
  const { editor } = setup([line("masked", at("10"), at("12"))])
  assert.deepEqual(ids(editor.trackGeojson), ["flight"])
})
test("missing flight times retain GPS while still displaying the flight", () => {
  const { c, editor } = setup()
  c.flightsGeoJSON = fc([{ ...flight, properties: { id: "flight" } }])
  editor.provider = c.posterProvider()
  assert.deepEqual(ids(editor.trackGeojson), [
    "ground",
    "masked",
    "partial",
    "flight",
  ])
})
test("the untimed overview fallback is retained when day routes have not loaded", () => {
  const { c, editor } = setup()
  c.dayRoutesLayer = null
  editor.provider = c.posterProvider()
  assert.deepEqual(ids(editor.trackGeojson), [undefined, "flight"])
})

test("an explicit empty poster snapshot survives, and legacy providers still render GPS", () => {
  const editor = new Editor()
  const raw = fc([line("raw", at("09"), at("10"))])
  editor.provider = new TripProvider({ geojson: raw, posterGeojson: fc([]) })
  assert.deepEqual(editor.trackGeojson, fc([]))
  assert.equal(editor.provider.trackGeojson(), raw)
  editor.provider = { trackGeojson: () => raw }
  assert.equal(editor.trackGeojson, raw)
})

test("gallery eligibility uses server GPS even when only an arc is in the frame", () => {
  const editor = new Editor()
  const nearby = fc([
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates: [
          [0, 0],
          [0.001, 0.001],
        ],
      },
      properties: {},
    },
  ])
  const distant = fc([line("distant", at("10"), at("12"))])
  Object.assign(editor, {
    hasSaveButtonTarget: true,
    saveButtonTarget: {},
    saveNoticeTarget: { classList: { toggle() {} } },
    previewMap: {
      getCenter: () => ({ lat: 0, lng: 0 }),
      getBounds: () => ({ getNorth: () => 0.005, getSouth: () => -0.005 }),
    },
  })
  editor.provider = new TripProvider({
    geojson: distant,
    posterGeojson: nearby,
  })
  editor.syncSaveAvailability()
  assert.equal(editor.saveButtonTarget.disabled, true)
  assert.equal(
    editor.saveNoticeTarget.textContent,
    "poster.no_tracks_in_frame poster.gallery_without_flights",
  )
  editor.provider = new TripProvider({
    geojson: nearby,
    posterGeojson: distant,
  })
  editor.syncSaveAvailability()
  assert.equal(editor.saveButtonTarget.disabled, false)
  assert.equal(
    editor.saveNoticeTarget.textContent,
    "poster.gallery_without_flights",
  )
  editor.provider = new TripProvider({ geojson: nearby })
  editor.syncSaveAvailability()
  assert.equal(editor.saveNoticeTarget.textContent, "")
  editor.provider = new TripProvider({ geojson: fc([]), posterGeojson: nearby })
  editor.syncSaveAvailability()
  assert.equal(editor.saveButtonTarget.disabled, true)
  assert.equal(
    editor.saveNoticeTarget.textContent,
    "poster.no_location_data poster.gallery_without_flights",
  )
})
