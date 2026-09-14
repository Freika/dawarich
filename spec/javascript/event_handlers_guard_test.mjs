import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/event_handlers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
const { shouldShowPointPopup, EventHandlers } = await import(moduleUrl)

test("a real single point shows its popup", () => {
  assert.equal(shouldShowPointPopup({ id: 42 }), true)
  assert.equal(shouldShowPointPopup({ id: 42, count: 1 }), true)
})

test("aggregate features without an id show no popup", () => {
  assert.equal(shouldShowPointPopup({}), false)
  assert.equal(shouldShowPointPopup({ count: 250 }), false)
})

test("merged cells carrying an arbitrary representative show no popup", () => {
  assert.equal(shouldShowPointPopup({ id: 42, count: 2 }), false)
})

test("an aggregate MVT Point zooms instead of opening an editor", () => {
  const movements = []
  const editorCalls = []
  const handlers = new EventHandlers(
    {
      easeTo: (options) => movements.push(options),
      getZoom: () => 8,
    },
    {
      layerManager: {
        getLayer: () => ({ justDragged: false }),
      },
      showInfo: () => {
        throw new Error("aggregate must not open point info")
      },
    },
  )
  handlers._openPointEditor = (...args) => editorCalls.push(args)

  handlers.handlePointClick({
    features: [
      {
        properties: { id: 42, count: 8 },
        layer: { id: "points-mvt" },
      },
    ],
    lngLat: { lng: 13.4, lat: 52.5 },
  })

  assert.equal(editorCalls.length, 0)
  assert.deepEqual(movements, [
    {
      center: { lng: 13.4, lat: 52.5 },
      zoom: 10,
      duration: 350,
    },
  ])
})

// The constructor registers document-level listeners; node has no DOM.
globalThis.document ??= {
  addEventListener: () => {},
  removeEventListener: () => {},
  dispatchEvent: () => {},
}

function loadSegmentsHarness(fetchedFeature) {
  const shown = []
  const selected = []
  const tracksLayer = {
    setSelectedTrack: (feature) => selected.push(feature),
    showSegments: (feature) => shown.push(feature),
    setSegmentHoverCallback: () => {},
    setSegmentLeaveCallback: () => {},
    clearSegmentHover: () => {},
  }
  const handlers = new EventHandlers(
    {},
    {
      api: { fetchTrackWithSegments: async () => fetchedFeature },
      layerManager: { getLayer: () => tracksLayer },
    },
  )
  handlers._createTrackSegmentMarkers = () => {}
  return { handlers, shown, selected }
}

test("a tiled track click swaps the clipped fragment for the fetched geometry", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const fetched = {
    properties: { id: 7 },
    geometry: {
      type: "LineString",
      coordinates: [
        [0, 0],
        [1, 1],
      ],
    },
  }
  const { handlers, shown, selected } = loadSegmentsHarness(fetched)

  await handlers._loadTrackSegments(7, fragment)

  assert.deepEqual(shown, [fetched])
  assert.deepEqual(selected, [fetched])
  assert.equal(handlers.selectedTrackFeature, fetched)
})

test("a fetched track without geometry keeps the clicked feature", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const { handlers, shown, selected } = loadSegmentsHarness({
    properties: { id: 7 },
  })

  await handlers._loadTrackSegments(7, fragment)

  assert.deepEqual(shown, [fragment])
  assert.deepEqual(selected, [])
})

test("a failed detail fetch on the tiled path surfaces a toast", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const toasts = []
  globalThis.Toast = { error: (message) => toasts.push(message) }
  globalThis.translate = (key) => key
  const { handlers } = loadSegmentsHarness(null)
  handlers.controller.api.fetchTrackWithSegments = async () => {
    throw new Error("network down")
  }

  await handlers._loadTrackSegments(7, fragment)
  assert.deepEqual(toasts, ["messages.failed_to_load_track_details"])
})
