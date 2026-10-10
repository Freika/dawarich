import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native map host drag commits a point revision and destroys its gesture", async () => {
  const f = fixture({ editEnabled: true })
  f.map.getZoom = () => 15
  f.map.getCanvasContainer = () => ({ style: {} })
  f.map.queryRenderedFeatures = () => [
    {
      type: "Feature",
      geometry: { type: "Point", coordinates: [13, 52] },
      properties: { id: 1, revision: 0, latitude: 52, longitude: 13 },
    },
  ]
  await f.owner.mount()
  f.map.emit("mousedown", {
    point: { x: 0, y: 0 },
    lngLat: { lng: 13, lat: 52 },
    preventDefault() {},
  })
  f.map.emit("mousemove", {
    point: { x: 10, y: 0 },
    lngLat: { lng: 14, lat: 53 },
  })
  await new Promise((resolve) => setImmediate(resolve))
  f.map.emit("mouseup", { lngLat: { lng: 14, lat: 53 } })
  await new Promise((resolve) => setImmediate(resolve))
  const move = f.pushed.find((e) => e.event === "point:move")
  assert.equal(move.payload.point_id, 1)
  assert.equal(move.payload.point.revision, 0)
  f.owner.destroy()
  assert.equal(f.listeners.get("mousedown").size, 0)
})
