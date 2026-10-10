import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native host selection action deletes accepted points and clears its DOM on destroy", async () => {
  const f = fixture(),
    panel = new Element()
  f.nodes.set("[data-map-selection]", panel)
  f.reader.pages = async () => [{ id: 7, anomaly: true }]
  f.reader.read = async () => ({ data: [] })
  await f.owner.mount()
  f.map.unproject = ([lng, lat]) => ({ lng, lat })
  f.owner.selection.start()
  f.map.emit("mousedown", { point: { x: 1, y: 2 } })
  f.map.emit("mouseup", { point: { x: 3, y: 4 } })
  await f.owner.selection.ready
  const remove = panel.children.find((item) => item["data-points"] === "all")
  assert.ok(remove)
  const original = globalThis.confirm
  globalThis.confirm = () => true
  try {
    remove.emit("click")
    const request = f.pushed.find((item) => item.event === "points:bulk_delete")
    assert.deepEqual(request.payload.point_ids, [7])
    request.reply({ ok: true, count: 1 })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(f.owner.selection.state.points, [])
  } finally {
    globalThis.confirm = original
    f.owner.destroy()
  }
  assert.deepEqual(panel.children, [])
})
