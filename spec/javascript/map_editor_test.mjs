import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/editing/map_editor.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const editingModule = async (name) =>
  (
    await readFile(
      new URL(
        `../../app/javascript/maps_maplibre/editing/${name}`,
        import.meta.url,
      ),
      "utf8",
    )
  )
    .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
    .replace(/^export /gm, "")
const editingModules = (
  await Promise.all(
    [
      "tile_exclusions.js",
      "editable_track_data.js",
      "point_edit_history.js",
      "point_edit_history_panel.js",
      "editor_history.js",
      "../utils/format_helpers.js",
    ].map(editingModule),
  )
).join("\n")
const dependencies = `${editingModules}
const translate = (key) => key
globalThis.__mapEditorToastErrors = []
globalThis.__mapEditorToasts = []
const Toast = {
  error(message) { globalThis.__mapEditorToastErrors.push(message) },
  show(message, type, duration, action) { globalThis.__mapEditorToasts.push({ message, type, duration, action }) },
}
class EditableTrackLayer {
  constructor() { this.pointsLayerId = "track-points"; this.successLayerId = "edit-success-indicator" }
  add(data) { this.data = data }
  setData(data) { this.data = data }
  remove() { this.data = null }
}
class EditSuccessIndicator {
  constructor() { this.shown = [] }
  show(id) { this.shown.push(id) }
  cancel() {}
}
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
const { MapEditor } = await import(moduleUrl)

let managerSource = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/map_data_manager.js",
    import.meta.url,
  ),
  "utf8",
)
managerSource = managerSource.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const managerDependencies = `
const flightWindows = (geoJSON) => geoJSON?.windows || []
`
const managerUrl = `data:text/javascript;base64,${Buffer.from(managerDependencies + managerSource).toString("base64")}`
const { MapDataManager } = await import(managerUrl)

globalThis.document = { dispatchEvent() {} }
globalThis.CustomEvent = class {
  constructor(type, options) {
    this.type = type
    this.detail = options.detail
  }
}

function fakeMap() {
  const handlers = new Map()
  const filters = new Map()
  return {
    handlers,
    filters,
    on(event, layerOrHandler, handler) {
      handlers.set(
        `${event}:${typeof layerOrHandler === "string" ? layerOrHandler : "map"}`,
        handler || layerOrHandler,
      )
    },
    once(event, handler) {
      handlers.set(`${event}:once`, handler)
    },
    off(event, layerOrHandler, handler) {
      const key = `${event}:${typeof layerOrHandler === "string" ? layerOrHandler : "map"}`
      const callback = handler || layerOrHandler
      if (handlers.get(key) === callback) handlers.delete(key)
    },
    getCanvasContainer() {
      return { style: {} }
    },
    getLayer() {
      return { id: "layer" }
    },
    getFilter(id) {
      return filters.get(id) || null
    },
    setFilter(id, filter) {
      filters.set(id, filter)
    },
    listenerCount(event, layer = "map") {
      return handlers.has(`${event}:${layer}`) ? 1 : 0
    },
  }
}

function trackFeature(
  revision = 4,
  coordinates = [
    [0, 0],
    [2, 0],
  ],
  segments = [],
) {
  return {
    type: "Feature",
    geometry: { type: "LineString", coordinates },
    properties: { id: 10, revision, segments },
  }
}

function point(id, longitude, latitude, revision = 2) {
  return {
    id,
    longitude: String(longitude),
    latitude: String(latitude),
    revision,
  }
}

test("import editor exposes only selected Points and keeps scoped Track geometry after a move", async () => {
  const map = fakeMap()
  const highlights = []
  const scopedFeature = {
    ...trackFeature(),
    geometry: {
      type: "MultiLineString",
      coordinates: [
        [
          [0, 0],
          [2, 0],
        ],
      ],
    },
  }
  const editor = new MapEditor(map, {
    apiClient: {
      importId: "42",
      fetchTrackWithSegments: async () => scopedFeature,
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async () => ({
        point: point(1, 1, 0, 3),
        track: trackFeature(5, [
          [1, 0],
          [9, 0],
        ]),
        revision: { point: 3, track: 5 },
      }),
    },
    layerManager: {
      getLayer(name) {
        if (name === "tracks")
          return { setSelectedTrack: (feature) => highlights.push(feature) }
        return { refresh() {} }
      },
    },
    historyScope: () => ({}),
  })

  await editor.selectTrack(10)
  assert.equal(editor._track(), undefined)
  assert.equal(map.filters.get("tracks-mvt"), undefined)
  assert.deepEqual(
    editor._points().map((feature) => feature.properties.id),
    [1, 2],
  )

  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 0.5, lat: 0 } })
  await editor.onMouseUp({ lngLat: { lng: 1, lat: 0 } })
  await new Promise(setImmediate)

  assert.equal(editor.trackRevision, 5)
  assert.deepEqual(highlights.at(-1), scopedFeature)
  assert.equal(editor._track(), undefined)
})

test("drag previews point and track locally, then sends exactly one composite mutation", async () => {
  const calls = []
  const refreshes = []
  const apiClient = {
    fetchTrackWithSegments: async () => trackFeature(),
    fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    movePointPosition: async (id, attributes) => {
      calls.push({ id, attributes })
      return {
        point: point(1, 1, 1, 3),
        track: trackFeature(5, [
          [1, 1],
          [2, 0],
        ]),
        revision: { point: 3, track: 5 },
        visited_countries: null,
      }
    },
  }
  const layerManager = {
    getLayer(name) {
      return { refresh: () => refreshes.push(name) }
    },
  }
  const editor = new MapEditor(fakeMap(), {
    apiClient,
    layerManager,
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)

  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 0.5, lat: 0.5 } })
  assert.deepEqual(editor._track().geometry.coordinates, [
    [0.5, 0.5],
    [2, 0],
  ])
  assert.equal(calls.length, 0)

  await editor.onMouseUp({ lngLat: { lng: 1, lat: 1 } })

  assert.equal(calls.length, 1)
  assert.equal(calls[0].attributes.pointRevision, 2)
  assert.equal(calls[0].attributes.trackRevision, 4)
  assert.deepEqual(editor._track().geometry.coordinates, [
    [1, 1],
    [2, 0],
  ])
  assert.deepEqual(refreshes, ["points-mvt", "tracks-mvt"])
})

test("a second drag is ignored while the same track has a mutation in flight", async () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  editor.inFlight = true

  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })

  assert.equal(editor.draggedPointId, null)
})

test("newer realtime revisions replace overlay state and stale ones are ignored", async () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  editor.applyRealtime({
    point: point(1, 9, 9, 3),
    track: trackFeature(3, [
      [9, 9],
      [2, 0],
    ]),
    revision: { point: 3, track: 3 },
  })
  assert.deepEqual(editor._track().geometry.coordinates, [
    [0, 0],
    [2, 0],
  ])

  editor.applyRealtime({
    point: point(1, 3, 3, 5),
    track: trackFeature(6, [
      [3, 3],
      [2, 0],
    ]),
    revision: { point: 5, track: 6 },
  })
  assert.deepEqual(editor._track().geometry.coordinates, [
    [3, 3],
    [2, 0],
  ])
})

test("drag previews index-anchored segment geometry on every local move", async () => {
  const segment = {
    id: 91,
    start_index: 0,
    end_index: 1,
    coordinates: [
      [0, 0],
      [2, 0],
    ],
  }
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () =>
        trackFeature(
          4,
          [
            [0, 0],
            [2, 0],
          ],
          [segment],
        ),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)

  editor.preview(1, 0.5, 0.75)

  assert.deepEqual(editor._segments()[0].geometry.coordinates, [
    [0.5, 0.75],
    [2, 0],
  ])
})

test("trackless point accepts only a newer realtime point revision", () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {},
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  editor.selectPoint({ properties: point(7, 1, 2, 3) })

  assert.equal(
    editor.applyRealtime({ point: point(7, 4, 5, 3), revision: { point: 3 } }),
    false,
  )
  assert.equal(
    editor.applyRealtime({ point: point(7, 6, 7, 4), revision: { point: 4 } }),
    true,
  )
  assert.deepEqual(editor._point(7).geometry.coordinates, [6, 7])
  assert.equal(editor._point(7).properties.track_id, undefined)
})

test("a conflict applies server state and explains that the other edit won", async () => {
  globalThis.__mapEditorToastErrors.length = 0
  const conflict = new Error("conflict")
  conflict.status = 409
  conflict.payload = {
    point: point(1, 8, 9, 4),
    track: trackFeature(6, [
      [8, 9],
      [2, 0],
    ]),
    revision: { point: 4, track: 6 },
  }
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async () => {
        throw conflict
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 4, lat: 5 } })
  await editor.onMouseUp({ lngLat: { lng: 4, lat: 5 } })

  assert.deepEqual(editor._point(1).geometry.coordinates, [8, 9])
  assert.deepEqual(editor._track().geometry.coordinates, [
    [8, 9],
    [2, 0],
  ])
  assert.deepEqual(globalThis.__mapEditorToastErrors, [
    "messages.point_edit_conflict",
  ])
})

test("a failed mutation restores the complete pre-drag snapshot", async () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async () => {
        throw new Error("offline")
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  const before = JSON.parse(JSON.stringify(editor.data))
  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 4, lat: 5 } })
  await editor.onMouseUp({ lngLat: { lng: 4, lat: 5 } })

  assert.deepEqual(editor.data, before)
})

test("a mutation response cannot overwrite a newer edit session", async () => {
  let resolveMove
  const move = new Promise((resolve) => {
    resolveMove = resolve
  })
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async () => move,
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 4, lat: 5 } })
  const pending = editor.onMouseUp({ lngLat: { lng: 4, lat: 5 } })
  editor.selectPoint({ properties: point(7, 7, 7, 1) })

  resolveMove({
    point: point(1, 8, 9, 3),
    track: trackFeature(5, [
      [8, 9],
      [2, 0],
    ]),
    revision: { point: 3, track: 5 },
  })
  await pending

  assert.equal(editor.trackId, null)
  assert.deepEqual(editor._point(7).geometry.coordinates, [7, 7])
})

test("a click without pointer movement closes the drag without a request", async () => {
  let calls = 0
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async () => {
        calls += 1
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)
  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })

  await editor.onMouseUp({ lngLat: { lng: 0, lat: 0 } })

  assert.equal(calls, 0)
  assert.equal(editor.draggedPointId, null)
})

test("sequential edits retain the session and use returned revisions", async () => {
  const calls = []
  let revision = 4
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async (_id, attributes) => {
        calls.push(attributes)
        revision += 1
        return {
          point: point(1, attributes.longitude, attributes.latitude, revision),
          track: trackFeature(revision, [
            [attributes.longitude, attributes.latitude],
            [2, 0],
          ]),
          revision: { point: revision, track: revision },
        }
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)

  for (const [lng, lat] of [
    [0.5, 0.5],
    [0.75, 0.75],
  ]) {
    editor.onMouseDown({
      features: [{ properties: { id: 1 } }],
      preventDefault() {},
    })
    editor.onMouseMove({ lngLat: { lng, lat } })
    await editor.onMouseUp({ lngLat: { lng, lat } })
  }

  assert.equal(calls.length, 2)
  assert.equal(calls[0].trackRevision, 4)
  assert.equal(calls[1].trackRevision, 5)
  assert.equal(calls[1].pointRevision, 5)
  assert.equal(editor.trackId, 10)
  assert.equal(editor.trackRevision, 6)
})

test("time-anchored segments preview only Points inside their timestamps", async () => {
  const segment = {
    id: 92,
    start_time: 110,
    end_time: 120,
    coordinates: [[1, 0]],
  }
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () =>
        trackFeature(
          4,
          [
            [0, 0],
            [1, 0],
            [2, 0],
          ],
          [segment],
        ),
      fetchTrackPoints: async () => [
        { ...point(1, 0, 0), timestamp: 100 },
        { ...point(2, 1, 0), timestamp: 110 },
        { ...point(3, 2, 0), timestamp: 120 },
      ],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)

  editor.preview(3, 2.5, 0.5)

  assert.deepEqual(editor._segments()[0].geometry.coordinates, [
    [1, 0],
    [2.5, 0.5],
  ])
})

test("tile refresh reapplies exclusions and close restores the newest base filters", async () => {
  const map = fakeMap()
  const initialTrackFilter = ["==", ["get", "visible"], true]
  const initialPointFilter = [">", ["get", "timestamp"], 100]
  map.filters.set("tracks-mvt", initialTrackFilter)
  map.filters.set("points-mvt", initialPointFilter)
  const editor = new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({ startAt: "100", endAt: "200" }),
  })
  await editor.selectTrack(10)

  const refreshedTrackFilter = ["==", ["get", "range"], "new"]
  const refreshedPointFilter = [">", ["get", "timestamp"], 200]
  map.filters.set("tracks-mvt", refreshedTrackFilter)
  map.filters.set("points-mvt", refreshedPointFilter)
  editor.reapplyTileFilters()
  assert.deepEqual(map.filters.get("tracks-mvt"), [
    "all",
    refreshedTrackFilter,
    ["!=", ["get", "id"], 10],
  ])

  editor.close()

  assert.deepEqual(map.filters.get("tracks-mvt"), refreshedTrackFilter)
  assert.deepEqual(map.filters.get("points-mvt"), refreshedPointFilter)
  assert.equal(map.listenerCount("mousedown", "track-points"), 0)
  assert.equal(map.listenerCount("mousemove"), 0)
  assert.equal(map.listenerCount("mouseup"), 0)
})

test("flight toggles preserve edit exclusions and closing restores the current mask", async () => {
  const map = fakeMap()
  const layers = {
    flights: { visible: false },
    "points-mvt": {
      setFlightWindows: (windows) =>
        map.setFilter(
          "points-mvt",
          windows.length ? ["flight-points", windows] : null,
        ),
    },
    "tracks-mvt": {
      setFlightWindows: (windows) =>
        map.setFilter(
          "tracks-mvt",
          windows.length ? ["flight-tracks", windows] : null,
        ),
    },
  }
  const layerManager = { getLayer: (name) => layers[name] }
  const editor = new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager,
    historyScope: () => ({}),
  })
  layers["map-editor"] = editor
  const manager = new MapDataManager({ map, layerManager })
  manager.lastLoadedData = { flightsGeoJSON: { windows: [[100, 200]] } }

  await editor.selectTrack(10)
  layers.flights.visible = true
  manager.applyFlightMask()
  const trackMask = ["flight-tracks", [[100, 200]]]
  const pointMask = ["flight-points", [[100, 200]]]
  assert.deepEqual(map.getFilter("tracks-mvt"), [
    "all",
    trackMask,
    ["!=", ["get", "id"], 10],
  ])
  assert.deepEqual(map.getFilter("points-mvt"), [
    "all",
    pointMask,
    ["!", ["in", ["get", "id"], ["literal", [1, 2]]]],
  ])

  layers.flights.visible = false
  manager.applyFlightMask()
  assert.deepEqual(map.getFilter("tracks-mvt"), ["!=", ["get", "id"], 10])
  editor.close()
  assert.equal(map.getFilter("tracks-mvt"), null)
  assert.equal(map.getFilter("points-mvt"), null)

  layers.flights.visible = true
  manager.applyFlightMask()
  await editor.selectTrack(10)
  editor.close()
  assert.deepEqual(map.getFilter("tracks-mvt"), trackMask)
  assert.deepEqual(map.getFilter("points-mvt"), pointMask)
})

test("successful point move refreshes tiles even after the editor closes", async () => {
  const map = fakeMap()
  const refreshed = []
  const events = []
  const originalDispatch = document.dispatchEvent
  document.dispatchEvent = (event) => events.push(event.type)
  let completeMove
  const editor = new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: () =>
        new Promise((resolve) => {
          completeMove = resolve
        }),
    },
    layerManager: {
      getLayer: (name) => ({ refresh: () => refreshed.push(name) }),
    },
    historyScope: () => ({}),
  })

  try {
    await editor.selectTrack(10)
    editor.onMouseDown({
      features: [{ properties: { id: 1 } }],
      preventDefault() {},
    })
    editor.onMouseMove({ lngLat: { lng: 1, lat: 1 } })
    const pendingMove = editor.onMouseUp({ lngLat: { lng: 1, lat: 1 } })
    editor.close()
    completeMove({ point: point(1, 1, 1, 3), revision: { point: 3 } })
    await pendingMove

    assert.deepEqual(refreshed, ["points-mvt", "tracks-mvt"])
    assert.deepEqual(events, ["dawarich:point-moved"])
    assert.equal(editor.data, null)
    assert.deepEqual(editor.indicator.shown, [])
  } finally {
    document.dispatchEvent = originalDispatch
  }
})

function tilePoint(
  id,
  longitude,
  latitude,
  { trackId = 10, revision = 2 } = {},
) {
  return {
    properties: {
      id,
      track_id: trackId,
      revision,
      longitude: String(longitude),
      latitude: String(latitude),
    },
  }
}

function deferred() {
  let resolve
  const promise = new Promise((done) => {
    resolve = done
  })
  return { promise, resolve }
}

test("a drag started on a tile point waits for its track before saving, and sends the track revision", async () => {
  const trackLoad = deferred()
  const calls = []
  const map = fakeMap()
  const editor = new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: () =>
        trackLoad.promise.then(() => trackFeature(4)),
      fetchTrackPoints: () =>
        trackLoad.promise.then(() => [point(1, 0, 0, 2), point(2, 2, 0)]),
      movePointPosition: async (id, attributes) => {
        calls.push({ id, attributes, trackFilter: map.getFilter("tracks-mvt") })
        return {
          point: point(1, 1, 1, 3),
          track: trackFeature(5, [
            [1, 1],
            [2, 0],
          ]),
          revision: { point: 3, track: 5 },
        }
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })

  assert.equal(editor.beginTileDrag(tilePoint(1, 0, 0)), true)
  editor.dragTo(0.5, 0.5)
  const saving = editor.endDrag({ lng: 1, lat: 1 })
  await Promise.resolve()
  assert.equal(calls.length, 0)

  trackLoad.resolve()
  await saving

  assert.equal(calls.length, 1)
  assert.equal(calls[0].attributes.trackRevision, 4)
  assert.equal(calls[0].attributes.longitude, 1)
  assert.equal(calls[0].attributes.latitude, 1)
  assert.deepEqual(calls[0].trackFilter, ["!=", ["get", "id"], 10])
})

test("a track that arrives mid-drag follows the dragged point", async () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })

  editor.beginTileDrag(tilePoint(1, 0, 0))
  editor.dragTo(0.5, 0.5)
  await editor.trackLoad

  assert.deepEqual(editor._track().geometry.coordinates, [
    [0.5, 0.5],
    [2, 0],
  ])
})

test("a tile point without a track saves without waiting for one", async () => {
  const calls = []
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      movePointPosition: async (_id, attributes) => {
        calls.push(attributes)
        return { point: point(7, 1, 1, 3), revision: { point: 3 } }
      },
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })

  editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null }))
  editor.dragTo(1, 1)
  await editor.endDrag({ lng: 1, lat: 1 })

  assert.equal(calls.length, 1)
  assert.equal(calls[0].trackRevision, null)
})

test("a saved move can be undone from the edit history with the new revisions", async () => {
  globalThis.__mapEditorToasts.length = 0
  const calls = []
  const refreshed = []
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(4),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
      movePointPosition: async (id, attributes) => {
        calls.push({ id, attributes })
        const revision = calls.length === 1 ? 3 : 4
        return {
          point: point(1, attributes.longitude, attributes.latitude, revision),
          track: trackFeature(revision + 2, [
            [attributes.longitude, attributes.latitude],
            [2, 0],
          ]),
          revision: { point: revision, track: revision + 2 },
        }
      },
    },
    layerManager: {
      getLayer: (name) => ({ refresh: () => refreshed.push(name) }),
    },
    historyScope: () => ({}),
  })
  await editor.selectTrack(10)
  editor.onMouseDown({
    features: [{ properties: { id: 1 } }],
    preventDefault() {},
  })
  editor.onMouseMove({ lngLat: { lng: 1, lat: 1 } })
  await editor.onMouseUp({ lngLat: { lng: 1, lat: 1 } })

  assert.equal(editor.edits.history.canUndo, true)
  assert.deepEqual(globalThis.__mapEditorToasts, [])

  refreshed.length = 0
  await editor.edits.undo()

  assert.equal(calls.length, 2)
  assert.deepEqual(calls[1], {
    id: 1,
    attributes: {
      longitude: 0,
      latitude: 0,
      pointRevision: 3,
      trackRevision: 5,
      historyScope: {},
    },
  })
  assert.deepEqual(editor._point(1).geometry.coordinates, [0, 0])
  assert.deepEqual(refreshed, ["points-mvt", "tracks-mvt"])
  assert.equal(editor.edits.history.canRedo, true)
})

test("an undo that lost to another edit explains the conflict", async () => {
  globalThis.__mapEditorToasts.length = 0
  globalThis.__mapEditorToastErrors.length = 0
  let calls = 0
  const editor = new MapEditor(fakeMap(), {
    apiClient: {
      movePointPosition: async () => {
        calls += 1
        if (calls === 1)
          return { point: point(7, 1, 1, 3), revision: { point: 3 } }
        const error = new Error("conflict")
        error.status = 409
        error.payload = { point: point(7, 5, 5, 9), revision: { point: 9 } }
        throw error
      },
    },
    layerManager: { getLayer: () => ({ refresh() {} }) },
    historyScope: () => ({}),
  })
  editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null }))
  editor.dragTo(1, 1)
  await editor.endDrag({ lng: 1, lat: 1 })

  await editor.edits.undo()

  assert.deepEqual(globalThis.__mapEditorToastErrors, [
    "messages.point_edit_conflict",
  ])
  assert.deepEqual(editor._point(7).geometry.coordinates, [5, 5])
})

test("a cancelled drag puts the point back without saving", () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {},
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })
  editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null }))
  editor.dragTo(3, 3)

  editor.cancelDrag()

  assert.deepEqual(editor._point(7).geometry.coordinates, [0, 0])
  assert.equal(editor.draggedPointId, null)
})

test("a read-only editor refuses a tile drag", () => {
  const editor = new MapEditor(fakeMap(), {
    apiClient: {},
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
    editable: false,
  })

  assert.equal(
    editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null })),
    false,
  )
  assert.equal(editor.data ?? null, null)
})

test("reapplying exclusions over filters that still carry them does not nest them", async () => {
  const map = fakeMap()
  const base = ["==", ["get", "visible"], true]
  map.filters.set("tracks-mvt", base)
  const editor = new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })
  await editor.selectTrack(10)

  editor.reapplyTileFilters()
  editor.reapplyTileFilters()

  assert.deepEqual(map.filters.get("tracks-mvt"), [
    "all",
    base,
    ["!=", ["get", "id"], 10],
  ])
  editor.close()
  assert.deepEqual(map.filters.get("tracks-mvt"), base)
})

function viewOnlyEditor(map = fakeMap()) {
  return new MapEditor(map, {
    apiClient: {
      fetchTrackWithSegments: async () => trackFeature(),
      fetchTrackPoints: async () => [point(1, 0, 0), point(2, 2, 0)],
    },
    layerManager: { getLayer: () => null },
    historyScope: () => ({}),
  })
}

test("turning editing off closes a track opened for editing", async () => {
  const map = fakeMap()
  const editor = viewOnlyEditor(map)
  await editor.selectTrack(10, { forEditing: true })

  editor.setEditable(false)

  assert.equal(editor.data, null)
  assert.equal(map.getFilter("tracks-mvt"), null)
})

test("turning editing off closes a point dragged from the tiles", () => {
  const editor = viewOnlyEditor()
  editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null }))
  editor.cancelDrag()

  editor.setEditable(false)

  assert.equal(editor.data, null)
})

test("turning editing off keeps a track's points open for viewing", async () => {
  const editor = viewOnlyEditor()
  await editor.selectTrack(10)

  editor.setEditable(false)

  assert.notEqual(editor.data, null)
})

test("the edit history panel appears after a move and goes away when editing is turned off", async () => {
  const map = fakeMap()
  const controls = []
  map.addControl = (control, position) => {
    control.container = { position }
    controls.push(position)
  }
  map.removeControl = (control) => {
    control.container = null
    controls.push("removed")
  }
  const editor = new MapEditor(map, {
    apiClient: {
      movePointPosition: async () => ({
        point: point(7, 1, 1, 3),
        revision: { point: 3 },
      }),
    },
    layerManager: { getLayer: () => ({ refresh() {} }) },
    historyScope: () => ({}),
  })
  editor.edits.panel.render = () => {}

  editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null }))
  editor.dragTo(1, 1)
  await editor.endDrag({ lng: 1, lat: 1 })
  assert.deepEqual(controls, ["bottom-left"])

  editor.setEditable(false)
  assert.deepEqual(controls, ["bottom-left", "removed"])
})

test("closing the edit history panel hides it until the next move", async () => {
  const map = fakeMap()
  const controls = []
  map.addControl = (control) => {
    control.container = {}
    controls.push("shown")
  }
  map.removeControl = (control) => {
    control.container = null
    controls.push("hidden")
  }
  let revision = 2
  const editor = new MapEditor(map, {
    apiClient: {
      movePointPosition: async () => {
        revision += 1
        return {
          point: point(7, 1, 1, revision),
          revision: { point: revision },
        }
      },
    },
    layerManager: { getLayer: () => ({ refresh() {} }) },
    historyScope: () => ({}),
  })
  editor.edits.panel.render = () => {}
  const move = async (lng) => {
    editor.beginTileDrag(tilePoint(7, 0, 0, { trackId: null, revision }))
    editor.dragTo(lng, lng)
    await editor.endDrag({ lng, lat: lng })
  }

  await move(1)
  editor.edits.close()
  assert.deepEqual(controls, ["shown", "hidden"])
  assert.equal(editor.edits.history.canUndo, true)

  await move(2)
  assert.deepEqual(controls, ["shown", "hidden", "shown"])
})
