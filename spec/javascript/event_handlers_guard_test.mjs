import assert from "node:assert/strict"
import test from "node:test"
import { strippedSource } from "./support/stripped_source.mjs"

const withoutImports = await strippedSource(
  "controllers/maps/maplibre/event_handlers.js",
  { inline: ["controllers/maps/maplibre/track_selection.js"] },
)
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
      timelineBridge: {},
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
      timelineBridge: {},
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
      timelineBridge: {},
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
    timelineBridge: {},
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
  handlers.trackSelection.markers = [
    { remove: () => removed.push(1) },
    { remove: () => removed.push(2) },
  ]

  handlers.teardownLayerInteractions()

  assert.deepEqual(removed, [1, 2])
  assert.deepEqual(handlers.trackSelection.markers, [])
  assert.equal(handlers.selectedTrackFeature, null)
})

function editablePointHandlers({ editor, tileHits = [] }) {
  const shown = []
  const handlers = new EventHandlers(
    {
      getLayer: (id) => id === "points-mvt",
      queryRenderedFeatures: (_point, { layers }) =>
        layers.includes("points-mvt") ? tileHits : [],
    },
    { layerManager: { getLayer: () => editor } },
  )
  handlers._showPointFeature = (feature) => shown.push(feature.properties.id)
  return { handlers, shown }
}

const editedPointClick = {
  point: { x: 10, y: 10 },
  features: [{ properties: { id: 102 }, layer: { id: "track-points" } }],
}

test("clicking a point of the edited track selects it", () => {
  const { handlers, shown } = editablePointHandlers({
    editor: { forEditing: true, justDragged: false },
  })
  handlers.handleEditablePointClick(editedPointClick)
  assert.deepEqual(shown, [102])
})

test("the click that ends a drag keeps the current selection", () => {
  const { handlers, shown } = editablePointHandlers({
    editor: { forEditing: true, justDragged: true },
  })
  handlers.handleEditablePointClick(editedPointClick)
  assert.deepEqual(shown, [])
})

test("a tile point under the click is selected instead of the edited point", () => {
  const { handlers, shown } = editablePointHandlers({
    editor: { forEditing: true, justDragged: false },
    tileHits: [{ properties: { id: 7 }, layer: { id: "points-mvt" } }],
  })
  handlers.handleEditablePointClick(editedPointClick)
  assert.deepEqual(shown, [])
})

test("clearing a point selection keeps a highlighted day dimmed", () => {
  const reapplied = []
  const paints = []
  const handlers = new EventHandlers(
    {
      getLayer: () => true,
      setPaintProperty: (...args) => paints.push(args),
    },
    {
      timelineBridge: {
        highlightedDay: "2026-03-14",
        applyDayHighlight: (day) => reapplied.push(day),
      },
    },
  )

  handlers._restoreMainPointsOpacity()

  assert.deepEqual(reapplied, ["2026-03-14"])
  assert.deepEqual(paints, [])
})

test("clearing a point selection with no highlighted day restores opacity", () => {
  const paints = []
  const handlers = new EventHandlers(
    {
      getLayer: () => true,
      setPaintProperty: (...args) => paints.push(args),
    },
    { timelineBridge: {} },
  )

  handlers._restoreMainPointsOpacity()

  assert.deepEqual(paints, [
    ["points-mvt", "circle-opacity", 1],
    ["points-mvt", "circle-stroke-opacity", 1],
  ])
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
