import assert from "node:assert/strict"
import { test } from "node:test"
import {
  circlePolygon,
  createAreaEditor,
} from "../../app-phoenix/assets/js/map/ui/area_editor.js"

function mapMock() {
  const handlers = new Map()
  const sources = new Map()
  const layers = new Set()
  const canvas = { style: {} }
  return {
    handlers,
    sources,
    layers,
    canvas,
    on: (type, fn) => handlers.set(type, fn),
    off: (type, fn) => handlers.get(type) === fn && handlers.delete(type),
    getCanvas: () => canvas,
    addSource: (id, source) => {
      const stored = { ...source }
      stored.setData = (data) => {
        stored.data = data
      }
      sources.set(id, stored)
    },
    getSource: (id) => sources.get(id),
    removeSource: (id) => sources.delete(id),
    addLayer: (layer) => layers.add(layer.id),
    getLayer: (id) => layers.has(id),
    removeLayer: (id) => layers.delete(id),
  }
}

test("area editor pushes one owned click and releases the map on destroy", () => {
  const map = mapMock()
  const pushed = []
  const editor = createAreaEditor({
    map,
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })

  editor.arm()
  assert.equal(map.canvas.style.cursor, "crosshair")
  map.handlers.get("click")({ lngLat: { lng: 13.4049999, lat: 52.5200001 } })
  map.handlers.get("click")?.({ lngLat: { lng: 1, lat: 1 } })
  assert.deepEqual(pushed, [
    ["area:new", { latitude: 52.52, longitude: 13.405 }],
  ])
  assert.equal(map.canvas.style.cursor, "")

  editor.preview({ latitude: 52.52, longitude: 13.405, radius: "250" })
  assert.equal(map.layers.size, 2)
  editor.preview({ latitude: 52.52, longitude: 13.405, radius: "-4" })
  assert.equal(map.sources.get("native-area-preview").data.features.length, 0)

  editor.arm()
  editor.destroy()
  assert.equal(map.handlers.size, 0)
  assert.equal(map.sources.size, 0)
  assert.equal(map.layers.size, 0)
  assert.equal(map.canvas.style.cursor, "")
  editor.arm()
  assert.equal(map.handlers.size, 0)
})

test("circle preview keeps the radius in metres", () => {
  const ring = circlePolygon(52.52, 13.405, 1000).geometry.coordinates[0]
  assert.equal(ring.length, 65)
  assert.deepEqual(ring[0], ring[64])
  const north = ring[0]
  assert.ok(Math.abs((north[1] - 52.52) * 111320 - 1000) < 5)
})
