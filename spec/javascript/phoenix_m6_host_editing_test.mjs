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

const editTrack = {
  type: "Feature",
  geometry: {
    type: "LineString",
    coordinates: [
      [13, 52],
      [14, 53],
    ],
  },
  properties: { id: 9, revision: 0 },
}
const editPoints = [
  { id: 7, longitude: 13, latitude: 52, revision: 0 },
  { id: 8, longitude: 14, latitude: 53, revision: 0 },
]

test("date and import changes close selected edit geometry and reject deferred drag reads and replies", async () => {
  for (const change of [
    { startAt: "2026-03-30T00:00", endAt: "2026-03-30T23:59" },
    { importId: "29" },
  ]) {
    const f = fixture({ editEnabled: true })
    f.map.getCanvasContainer = () => ({ style: {} })
    f.reader.read = async () => ({ data: structuredClone(editTrack) })
    f.reader.pages = async () => structuredClone(editPoints)
    let pending, release
    try {
      await f.owner.mount()
      const editor = f.owner.editor
      await editor.selectTrack(9, { forEditing: true })
      assert.equal(editor.startDrag(7), true)
      editor.dragTo(14, 53)
      pending = editor.endDrag({ lng: 14, lat: 53 })
      const command = f.pushed.find((item) => item.event === "point:move")
      await f.owner.update({
        ...f.owner.config,
        revision: 2,
        range: { ...f.owner.config.range, ...change },
      })
      assert.equal(editor.data, null)
      assert.equal(f.layers.has("track-points"), false)
      assert.equal(editor.draggedPointId, null)
      command.reply({
        ok: true,
        response: {
          point: { ...editPoints[0], revision: 1 },
          revision: { point: 1 },
        },
      })
      await pending
      assert.equal(editor.data, null)
      assert.equal(editor.edits.history.size, 0)
      assert.equal(editor.mutationState.busy, false)
      f.reader.read = () =>
        new Promise((resolve) => {
          release = resolve
        })
      editor.beginTileDrag({
        geometry: { type: "Point", coordinates: [13, 52] },
        properties: { ...editPoints[0], track_id: 9 },
      })
      editor.dragTo(14, 53)
      const loading = editor.trackLoad
      await f.owner.update({
        ...f.owner.config,
        revision: 3,
        range: {
          ...f.owner.config.range,
          importId: "30",
          startAt: "2026-04-01",
        },
      })
      release({ data: editTrack })
      await loading
      await editor.endDrag({ lng: 14, lat: 53 })
      assert.equal(editor.data, null)
      assert.equal(
        f.pushed.filter((item) => item.event === "point:move").length,
        1,
      )
    } finally {
      release?.({ data: editTrack })
      f.owner.destroy()
      await pending
    }
  }
})

test("map edit invalidation closes stale active geometry and reopening reads the canonical revision without a drag", async () => {
  for (const receipt of [{ kinds: ["map_edits"] }, { kinds: ["reconnect"] }]) {
    const f = fixture({ editEnabled: true })
    f.map.getCanvasContainer = () => ({ style: {} })
    let revision = 0
    f.reader.read = async () => ({
      data: { ...editTrack, properties: { ...editTrack.properties, revision } },
    })
    f.reader.pages = async () =>
      editPoints.map((point) => ({
        ...point,
        revision,
        longitude: point.longitude + revision,
      }))
    let pending
    try {
      await f.owner.mount()
      const editor = f.owner.editor
      await editor.selectTrack(9, { forEditing: true })
      editor.startDrag(7)
      editor.dragTo(15, 54)
      pending = editor.endDrag({ lng: 15, lat: 54 })
      const oldCommand = f.pushed.find((item) => item.event === "point:move")
      revision = 1
      await f.owner.reconnect(receipt)
      assert.equal(editor.data, null)
      assert.equal(f.layers.has("track-points"), false)
      oldCommand.reply({
        ok: true,
        response: {
          point: { ...editPoints[0], revision: 1 },
          revision: { point: 1 },
        },
      })
      await pending
      assert.equal(editor.edits.history.size, 0)
      await editor.selectTrack(9, { forEditing: true })
      assert.equal(editor.trackRevision, 1)
      assert.deepEqual(editor._point(7).geometry.coordinates, [14, 52])
      assert.equal(
        f.pushed.filter((item) => item.event === "point:move").length,
        1,
      )
    } finally {
      f.owner.destroy()
      await pending
    }
  }
})
