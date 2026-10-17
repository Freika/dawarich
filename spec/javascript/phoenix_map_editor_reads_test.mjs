import assert from "node:assert/strict"
import test from "node:test"
import { createReader } from "../../app-phoenix/assets/js/map/data/reader.js"
import { readRouteSnapshot } from "../../app-phoenix/assets/js/map/data/route_snapshot.js"
import { createStudioSource } from "../../app-phoenix/assets/js/map/data/studio_source.js"
import { MapEditor } from "../../app-phoenix/assets/js/map/edit/editor.js"

test("native point moves undo and redo invalidate exact replay reads", async () => {
  let point = {
    id: 7,
    latitude: 52,
    longitude: 13,
    timestamp: 1774861200,
    revision: 0,
  }
  let release,
    first = true
  const reader = createReader({
    origin: "https://native.test",
    fetch: async () => {
      const saved = { ...point }
      if (first) {
        first = false
        await new Promise((resolve) => {
          release = resolve
        })
      }
      return {
        ok: true,
        status: 200,
        headers: new Headers({ "x-total-pages": "1" }),
        json: async () => [saved],
      }
    },
  })
  const state = {
    revision: 1,
    range: { startAt: "2026-03-30", endAt: "2026-03-31", timezone: "UTC" },
  }
  const source = createStudioSource({
    getState: () => state,
    readSnapshot: (config, options) =>
      readRouteSnapshot(reader, config, options),
  })
  const map = {
    on() {},
    off() {},
    getLayer: () => null,
    getCanvasContainer: () => ({ style: {} }),
  }
  const editor = new MapEditor(map, {
    invalidatePoints: () => reader.reset(),
    move: async (_id, position) => {
      point = {
        ...point,
        latitude: position.latitude,
        longitude: position.longitude,
        revision: point.revision + 1,
      }
      return { point, revision: { point: point.revision } }
    },
    createLayer: () => ({ add() {}, setData() {}, remove() {} }),
    createIndicator: () => ({ show() {}, cancel() {} }),
  })
  try {
    const pending = source.snapshot({ purpose: "replay" }).then(
      (data) => ({ data }),
      (error) => ({ error }),
    )
    editor.selectPoint({
      type: "Feature",
      geometry: { type: "Point", coordinates: [13, 52] },
      properties: { id: 7, revision: 0, latitude: 52, longitude: 13 },
    })
    editor.startDrag(7)
    editor.dragTo(14, 53)
    await editor.endDrag({ lng: 14, lat: 53 })
    release()
    assert.equal((await pending).error?.name, "AbortError")
    assert.equal(
      (await source.snapshot({ purpose: "replay" })).points[0].latitude,
      53,
    )
    await editor.edits.undo()
    assert.equal(
      (await source.snapshot({ purpose: "replay" })).points[0].latitude,
      52,
    )
    await editor.edits.redo()
    assert.equal(
      (await source.snapshot({ purpose: "replay" })).points[0].latitude,
      53,
    )
  } finally {
    editor.dispose()
    source.destroy()
    reader.destroy()
  }
})
