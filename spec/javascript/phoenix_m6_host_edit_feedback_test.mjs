import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native map point conflict restores canonical position and shows its translated error", async () => {
  const f = fixture({
      editEnabled: true,
      uiLabels: { "messages.point_edit_conflict": "Point changed elsewhere" },
    }),
    error = new Element()
  f.nodes.set("[data-map-edit-error]", error)
  f.map.getCanvasContainer = () => ({ style: {} })
  await f.owner.mount()
  const editor = f.owner.editor
  editor.selectPoint({
    geometry: { type: "Point", coordinates: [13, 52] },
    properties: { id: 7, longitude: 13, latitude: 52, revision: 0 },
  })
  editor.startDrag(7)
  editor.dragTo(14, 53)
  const pending = editor.endDrag({ lng: 14, lat: 53 })
  f.pushed
    .find((item) => item.event === "point:move")
    .reply({
      error: "stale",
      response: {
        point: { id: 7, longitude: 13.5, latitude: 52.5, revision: 1 },
        revision: { point: 1 },
      },
    })
  await pending
  assert.deepEqual(editor._point(7).geometry.coordinates, [13.5, 52.5])
  assert.deepEqual(editor.edits.history.entries, [])
  assert.equal(error.textContent, "Point changed elsewhere")
  f.owner.destroy()
})
