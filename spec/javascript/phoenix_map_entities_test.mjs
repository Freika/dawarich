import assert from "node:assert/strict"
import { test } from "node:test"
import { createEntityEditor } from "../../app-phoenix/assets/js/map/ui/entity_editor.js"

function mapMock() {
  const handlers = new Map()
  const canvas = { style: {} }
  return {
    handlers,
    canvas,
    on: (type, fn) => handlers.set(type, fn),
    off: (type, fn) => handlers.get(type) === fn && handlers.delete(type),
    getCanvas: () => canvas,
  }
}

test("entity click pushes one create, disarms, destroy removes listener", () => {
  const map = mapMock()
  const pushed = []
  const editor = createEntityEditor({
    map,
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })

  editor.arm("visit")
  assert.equal(map.canvas.style.cursor, "crosshair")
  map.handlers.get("click")({ lngLat: { lng: 13.4049999, lat: 52.5200001 } })
  map.handlers.get("click")?.({ lngLat: { lng: 1, lat: 1 } })
  assert.deepEqual(pushed, [
    ["visit:new", { latitude: 52.52, longitude: 13.405 }],
  ])
  assert.equal(map.canvas.style.cursor, "")

  editor.arm("unknown")
  assert.equal(map.handlers.size, 0)

  editor.arm("place")
  editor.destroy()
  assert.equal(map.handlers.size, 0)
  assert.equal(map.canvas.style.cursor, "")
  editor.arm("place")
  assert.equal(map.handlers.size, 0)
})

test("point address request carries only the point id", () => {
  const pushed = []
  const editor = createEntityEditor({
    map: mapMock(),
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })
  editor.address({ id: 7, properties: { street: "Main St" } })
  editor.destroy()
  editor.address({ id: 8 })
  assert.deepEqual(pushed, [["address:open", { id: 7 }]])
})
