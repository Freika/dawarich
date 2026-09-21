import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/editing/point_drag_gesture.js",
    import.meta.url,
  ),
  "utf8",
)
const { PointDragGesture } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const LONG_PRESS_MS = 5
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function fakeMap({ zoom = 15, tile = [], overlay = [] } = {}) {
  const handlers = new Map()
  const layers = { "points-mvt": tile, "track-points": overlay }
  const map = {
    zoom,
    handlers,
    dragPanEnabled: true,
    dragPan: {
      isEnabled: () => map.dragPanEnabled,
      disable: () => {
        map.dragPanEnabled = false
      },
      enable: () => {
        map.dragPanEnabled = true
      },
    },
    on(event, handler) {
      handlers.set(event, handler)
    },
    once(event, handler) {
      handlers.set(event, handler)
    },
    off(event, handler) {
      if (handlers.get(event) === handler) handlers.delete(event)
    },
    getZoom: () => map.zoom,
    getLayer: (id) => (layers[id]?.length ? { id } : undefined),
    queryRenderedFeatures: (_box, { layers: ids }) =>
      ids.flatMap((id) => layers[id] || []),
    fire(event, payload = {}) {
      let prevented = false
      const result = handlers.get(event)?.({
        point: { x: 0, y: 0 },
        lngLat: { lng: 0, lat: 0 },
        originalEvent: { button: 0, touches: [{}] },
        preventDefault() {
          prevented = true
        },
        ...payload,
      })
      return { prevented, result }
    },
  }
  return map
}

function fakeEditor({ accepts = true } = {}) {
  const calls = []
  return {
    calls,
    beginTileDrag(feature) {
      calls.push(["beginTileDrag", feature.properties.id])
      return accepts
    },
    startDrag(id) {
      calls.push(["startDrag", id])
      return accepts
    },
    dragTo(lng, lat) {
      calls.push(["dragTo", lng, lat])
    },
    async endDrag(lngLat) {
      calls.push(["endDrag", lngLat.lng, lngLat.lat])
    },
    cancelDrag() {
      calls.push(["cancelDrag"])
    },
  }
}

const singlePoint = (id) => ({ properties: { id } })
const isSinglePoint = (properties = {}) =>
  properties.id != null && (properties.count ?? 1) <= 1

function gestureFor(map, editor, { enabled = true } = {}) {
  const gesture = new PointDragGesture(map, {
    isEnabled: () => enabled,
    getEditor: async () => editor,
    isSinglePoint,
    longPressMs: LONG_PRESS_MS,
  })
  gesture.attach()
  return gesture
}

const at = (x, y, lng = x, lat = y) => ({
  point: { x, y },
  lngLat: { lng, lat },
})

test("dragging a tile point with the mouse moves it and saves on release", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  assert.equal(map.fire("mousedown", at(0, 0)).prevented, true)
  map.fire("mousemove", at(10, 0, 1, 1))
  await sleep(0)
  map.fire("mousemove", at(20, 0, 2, 2))
  await map.fire("mouseup", at(20, 0, 2, 2)).result

  assert.deepEqual(editor.calls, [
    ["beginTileDrag", 7],
    ["dragTo", 1, 1],
    ["dragTo", 2, 2],
    ["dragTo", 2, 2],
    ["endDrag", 2, 2],
  ])
})

test("a mouse press that barely moves stays a click", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("mousedown", at(0, 0))
  map.fire("mousemove", at(2, 1))
  await map.fire("mouseup", at(2, 1)).result

  assert.deepEqual(editor.calls, [])
})

test("a release before the editor loads still saves the drag", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("mousedown", at(0, 0))
  map.fire("mousemove", at(10, 0, 1, 1))
  await map.fire("mouseup", at(10, 0, 1, 1)).result

  assert.deepEqual(editor.calls.at(-1), ["endDrag", 1, 1])
})

test("points below the minimum zoom are not dragged and the map pans instead", () => {
  const map = fakeMap({ zoom: 13, tile: [singlePoint(7)] })
  const editor = fakeEditor()
  const gesture = gestureFor(map, editor)

  assert.equal(map.fire("mousedown", at(0, 0)).prevented, false)
  assert.equal(gesture.canDrag({ id: 7 }), false)
})

test("merged tile cells are not dragged", () => {
  const map = fakeMap({ tile: [{ properties: { id: 7, count: 4 } }] })
  gestureFor(map, fakeEditor())

  assert.equal(map.fire("mousedown", at(0, 0)).prevented, false)
})

test("nothing is dragged while editing is off", () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const gesture = gestureFor(map, fakeEditor(), { enabled: false })

  assert.equal(map.fire("mousedown", at(0, 0)).prevented, false)
  assert.equal(gesture.canDrag({ id: 7 }), false)
})

test("a point already open in the editor is left to the editor's own mouse drag", () => {
  const map = fakeMap({ tile: [singlePoint(7)], overlay: [singlePoint(7)] })
  gestureFor(map, fakeEditor())

  assert.equal(map.fire("mousedown", at(0, 0)).prevented, false)
})

test("a long press on a tile point starts a touch drag with map panning paused", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("touchstart", at(0, 0))
  await sleep(LONG_PRESS_MS * 3)
  assert.equal(map.dragPanEnabled, false)

  const move = map.fire("touchmove", at(30, 0, 3, 3))
  assert.equal(move.prevented, true)
  await map.fire("touchend", at(30, 0)).result

  assert.deepEqual(editor.calls.at(0), ["beginTileDrag", 7])
  assert.deepEqual(editor.calls.at(-1), ["endDrag", 3, 3])
  assert.equal(map.dragPanEnabled, true)
})

test("a long press on an open editor point drags it at any zoom", async () => {
  const map = fakeMap({ zoom: 10, overlay: [singlePoint(9)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("touchstart", at(0, 0))
  await sleep(LONG_PRESS_MS * 3)
  map.fire("touchmove", at(30, 0, 3, 3))
  await map.fire("touchend", at(30, 0)).result

  assert.deepEqual(editor.calls.at(0), ["startDrag", 9])
  assert.deepEqual(editor.calls.at(-1), ["endDrag", 3, 3])
})

test("moving the finger before the long press pans the map instead", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("touchstart", at(0, 0))
  const move = map.fire("touchmove", at(40, 0))
  await sleep(LONG_PRESS_MS * 3)

  assert.equal(move.prevented, false)
  assert.deepEqual(editor.calls, [])
  assert.equal(map.dragPanEnabled, true)
})

test("a cancelled touch puts the point back", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("touchstart", at(0, 0))
  await sleep(LONG_PRESS_MS * 3)
  map.fire("touchmove", at(30, 0, 3, 3))
  await map.fire("touchcancel").result

  assert.deepEqual(editor.calls.at(-1), ["cancelDrag"])
  assert.equal(map.dragPanEnabled, true)
})

test("a multi-finger touch is left to the map", async () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const editor = fakeEditor()
  gestureFor(map, editor)

  map.fire("touchstart", {
    ...at(0, 0),
    originalEvent: { touches: [{}, {}] },
  })
  await sleep(LONG_PRESS_MS * 3)

  assert.deepEqual(editor.calls, [])
})

test("detach removes the gesture's map listeners", () => {
  const map = fakeMap({ tile: [singlePoint(7)] })
  const gesture = gestureFor(map, fakeEditor())

  gesture.detach()

  assert.equal(map.handlers.size, 0)
})
