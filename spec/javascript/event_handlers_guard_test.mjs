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
const stubs = `class PointDragGesture {
  attach() {}
  detach() {}
  cancel() {}
  canDrag() { return false }
}
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(stubs + withoutImports).toString("base64")}`
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
        properties: { count: 8 },
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

test("a merged tile marker zooms without selecting its representative", () => {
  const selected = []
  const movements = []
  const handlers = new EventHandlers(
    {
      easeTo: (options) => movements.push(options),
      getZoom: () => 16,
      getMaxZoom: () => 22,
    },
    {
      layerManager: { getLayer: () => null },
    },
  )
  handlers._showPointFeature = (feature) => selected.push(feature)

  handlers.handlePointClick({
    features: [
      {
        properties: {
          id: 42,
          count: 8,
          timestamp: 0,
          longitude: "0",
          latitude: "0",
        },
        layer: { id: "points-mvt" },
      },
    ],
    lngLat: { lng: 13.4, lat: 52.5 },
  })

  assert.deepEqual(movements, [
    {
      center: { lng: 13.4, lat: 52.5 },
      zoom: 18,
      duration: 350,
    },
  ])
  assert.deepEqual(selected, [])
})

test("overlapping points at maximum zoom show no point actions", () => {
  const infos = []
  globalThis.translate = (key, values) =>
    values?.count ? `${key}: ${values.count}` : key
  const handlers = new EventHandlers(
    {
      getZoom: () => 22,
      getMaxZoom: () => 22,
      easeTo: () => {
        throw new Error("already at maximum zoom")
      },
    },
    {
      layerManager: { getLayer: () => null },
      showInfo: (...args) => infos.push(args),
    },
  )

  handlers.handlePointClick({
    features: [
      {
        properties: { id: 42, count: 2 },
        layer: { id: "points-mvt" },
      },
    ],
  })

  assert.deepEqual(infos, [
    ["map_info.location_point", "<p>map_info.overlapping_points: 2</p>"],
  ])
})

// The constructor registers document-level listeners; node has no DOM.
globalThis.document ??= {
  addEventListener: () => {},
  removeEventListener: () => {},
  dispatchEvent: () => {},
}

function loadSegmentsHarness(fetchedFeature, pointTileRange = undefined) {
  const shown = []
  const selected = []
  const fetches = []
  const tracksLayer = {
    setSelectedTrack: (feature) => selected.push(feature),
    showSegments: (feature) => shown.push(feature),
    hideSegments: () => {},
    setSegmentHoverCallback: () => {},
    setSegmentLeaveCallback: () => {},
    clearSegmentHover: () => {},
  }
  const handlers = new EventHandlers(
    { off: () => {}, getLayer: () => null },
    {
      api: {
        fetchTrackWithSegments: async (...args) => {
          fetches.push(args)
          return fetchedFeature
        },
      },
      layerManager: {
        pointTileRange,
        getLayer: (name) => (name === "tracks" ? tracksLayer : null),
      },
      closeInfo: () => {},
    },
  )
  handlers._createTrackSegmentMarkers = () => {}
  return { handlers, shown, selected, fetches }
}

test("a tiled track click fetches the track within the map's date range", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const range = {
    startAt: "2024-06-01T00:00+02:00",
    endAt: "2024-06-01T23:59+02:00",
  }
  const { handlers, fetches } = loadSegmentsHarness(
    { properties: { id: 7 } },
    range,
  )
  handlers.selectedTrackFeature = fragment

  await handlers._loadTrackSegments(7, fragment)

  assert.deepEqual(fetches, [[7, range]])
})

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
  handlers.selectedTrackFeature = fragment

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
  handlers.selectedTrackFeature = fragment

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
  handlers.selectedTrackFeature = fragment
  handlers.controller.api.fetchTrackWithSegments = async () => {
    throw new Error("network down")
  }

  await handlers._loadTrackSegments(7, fragment)
  assert.deepEqual(toasts, ["messages.failed_to_load_track_details"])
})

test("a late track-detail response cannot revive a cleared selection", async () => {
  const fragment = { properties: { id: 7 } }
  const { handlers, shown, selected } = loadSegmentsHarness(null)
  let resolveFetch
  handlers.controller.api.fetchTrackWithSegments = () =>
    new Promise((resolve) => {
      resolveFetch = resolve
    })
  handlers.selectedTrackFeature = fragment

  const pending = handlers._loadTrackSegments(7, fragment)
  handlers.clearTrackSelection()
  resolveFetch({ properties: { id: 7 }, geometry: { type: "LineString" } })
  await pending

  assert.deepEqual(shown, [])
  assert.deepEqual(selected, [null])
  assert.equal(handlers.selectedTrackFeature, null)
})

test("an older track-detail response cannot overwrite a newer click", async () => {
  const first = { properties: { id: 7 } }
  const second = { properties: { id: 8 } }
  const { handlers, shown } = loadSegmentsHarness(null)
  const requests = new Map()
  handlers.controller.api.fetchTrackWithSegments = (id) =>
    new Promise((resolve) => requests.set(id, resolve))

  handlers.selectedTrackFeature = first
  const older = handlers._loadTrackSegments(7, first)
  handlers._trackSelectionGeneration += 1
  handlers.selectedTrackFeature = second
  const newer = handlers._loadTrackSegments(8, second)
  requests.get(8)({ properties: { id: 8 }, geometry: { type: "LineString" } })
  await newer
  requests.get(7)({ properties: { id: 7 }, geometry: { type: "LineString" } })
  await older

  assert.deepEqual(
    shown.map((feature) => feature.properties.id),
    [8],
  )
  assert.equal(handlers.selectedTrackFeature.properties.id, 8)
})

test("clearing a point-only selection restores its editor and leaves info open", () => {
  const cleared = []
  const paint = []
  const closed = []
  const editor = { data: { features: [{}] }, clear: () => cleared.push(true) }
  const map = {
    off() {},
    getLayer: (name) => (name === "points-mvt" ? { id: name } : null),
    setPaintProperty: (...args) => paint.push(args),
  }
  const controller = {
    layerManager: {
      getLayer: (name) => (name === "map-editor" ? editor : null),
    },
    closeInfo: (options) => closed.push(options),
  }
  const handlers = new EventHandlers(map, controller)

  handlers.clearTrackSelection()
  assert.deepEqual(closed, [])
  handlers.clearPointSelection()

  assert.deepEqual(cleared, [true])
  assert.deepEqual(paint, [
    ["points-mvt", "circle-opacity", 1],
    ["points-mvt", "circle-stroke-opacity", 1],
  ])
  assert.deepEqual(closed, [])
})

test("tearing down track interactions removes segment markers", () => {
  const removed = []
  const handlers = new EventHandlers({ off() {} }, {})
  handlers.selectedTrackFeature = { properties: { id: 7 } }
  handlers.trackMarkers = [
    { remove: () => removed.push(1) },
    { remove: () => removed.push(2) },
  ]

  handlers.teardownLayerInteractions()

  assert.deepEqual(removed, [1, 2])
  assert.deepEqual(handlers.trackMarkers, [])
  assert.equal(handlers.selectedTrackFeature, null)
})

test("a track click claims the map click so the empty-map handler keeps the selection", () => {
  const handlers = new EventHandlers(
    { getLayer: () => undefined },
    {
      layerManager: { getLayer: () => undefined },
      api: { fetchTrackWithSegments: () => new Promise(() => {}) },
    },
  )
  let prevented = false

  handlers.handleTrackClick({
    point: { x: 1, y: 1 },
    preventDefault: () => {
      prevented = true
    },
    features: [
      {
        properties: { id: 7, start_at: "2025-10-15T10:00:00Z" },
        geometry: { type: "LineString", coordinates: [] },
      },
    ],
  })

  assert.equal(prevented, true)
})
