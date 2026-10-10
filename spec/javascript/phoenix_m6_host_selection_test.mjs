import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native host rectangle tool reads selection and Escape restores map gestures", async () => {
  const f = fixture()
  const button = new Element(),
    panel = new Element()
  f.nodes.set('[data-testid="native-select-area"]', button)
  f.nodes.set("[data-map-selection]", panel)
  f.reader.pages = async (resource) =>
    resource === "points" ? [{ id: 1 }] : [{ id: 2 }]
  f.map.unproject = ([lng, lat]) => ({ lng, lat })
  await f.owner.mount()
  button.emit("click")
  assert.equal(f.map.dragPan.isEnabled(), false)
  f.map.emit("mousedown", { point: { x: 1, y: 2 } })
  f.map.emit("mouseup", { point: { x: 3, y: 4 } })
  await f.owner.selection.ready
  assert.equal(f.owner.selection.state.points.length, 1)
  button.emit("click")
  f.root.emit("keydown", { key: "Escape" })
  assert.equal(f.map.dragPan.isEnabled(), true)
  assert.deepEqual(f.owner.selection.state.points, [])
  f.owner.destroy()
  assert.equal(button.listeners.get("click").size, 0)
})
