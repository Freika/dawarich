import assert from "node:assert/strict"
import test from "node:test"
import { createReader } from "../../app-phoenix/assets/js/map/data/reader.js"
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

test("native point editing reads every bounded cookie page with current import and cancellation", async () => {
  const f = fixture({ editEnabled: true })
  const requests = []
  const cookie = createReader({
    origin: "https://native.test",
    fetch: async (input, options) => {
      const url = new URL(input)
      requests.push({ url, options })
      const page = Number(url.searchParams.get("page") || 1)
      const rows =
        page === 1
          ? Array.from({ length: 1000 }, (_, i) => ({ id: i + 1 }))
          : [{ id: 1001 }]
      return new Response(JSON.stringify(rows), {
        headers: { "x-total-pages": "2" },
      })
    },
  })
  Object.assign(f.reader, cookie)
  try {
    await f.owner.mount()
    f.owner.config.range.importId = "29"
    const controller = new AbortController()
    const rows = await f.owner.editor.readPoints(7, {
      signal: controller.signal,
    })
    assert.equal(rows.length, 1001)
    assert.equal(rows.at(-1).id, 1001)
    assert.deepEqual(
      requests.map(({ url }) => url.searchParams.get("page")),
      ["1", "2"],
    )
    for (const { url, options } of requests) {
      assert.equal(url.pathname, "/native/map/data/tracks/7/points")
      assert.equal(url.searchParams.get("import_id"), "29")
      assert.equal(url.searchParams.get("per_page"), "1000")
      assert.equal(options.credentials, "same-origin")
      assert.equal(options.signal.aborted, false)
    }
    controller.abort()
    await assert.rejects(
      f.owner.editor.readPoints(7, { signal: controller.signal }),
      { name: "AbortError" },
    )
    assert.equal(requests.length, 2)
  } finally {
    f.owner.destroy()
  }
})
