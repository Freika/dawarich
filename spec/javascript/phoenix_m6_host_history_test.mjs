import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host accepted edits and undo share one translated history control", async () => {
  const f = fixture({
    editEnabled: true,
    uiLabels: { "messages.edit_history": "History" },
  })
  let control,
    removed = 0
  f.map.getCanvasContainer = () => ({ style: {} })
  f.map.addControl = (value) => {
    control = value
    value.onAdd()
  }
  f.map.removeControl = (value) => {
    removed++
    value.onRemove()
  }
  await f.owner.mount()
  assert.equal(f.owner.editor.edits.history, f.owner.pointEditing.history)
  f.owner.editor.indicator.show = () => {}
  f.owner.editor.selectPoint({
    type: "Feature",
    geometry: { type: "Point", coordinates: [13, 52] },
    properties: { id: 7, revision: 0, latitude: 52, longitude: 13 },
  })
  f.owner.editor.startDrag(7)
  f.owner.editor.dragTo(14, 53)
  const move = f.owner.editor.endDrag({ lng: 14, lat: 53 })
  f.pushed
    .find((item) => item.event === "point:move")
    .reply({
      ok: true,
      response: {
        point: { id: 7, latitude: 53, longitude: 14, revision: 1 },
        revision: { point: 1 },
      },
    })
  await move
  assert.equal(control.container["aria-label"], "History")
  const undo = f.owner.editor.edits.undo()
  const request = f.pushed.filter((item) => item.event === "point:move").at(-1)
  assert.equal(request.payload.point.revision, 1)
  request.reply({
    ok: true,
    response: {
      point: { id: 7, latitude: 52, longitude: 13, revision: 2 },
      revision: { point: 2 },
    },
  })
  await undo
  assert.equal(f.owner.editor.edits.history.undone.length, 1)
  f.owner.destroy()
  assert.equal(removed, 1)
  assert.equal(control.container, null)
})
