import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native host shortcuts activate owned controls ignore editors modifiers repeats and release", async () => {
  const f = fixture()
  const document = new Element()
  f.root.ownerDocument = document
  const activated = []
  for (const name of ["timeline", "layers", "search", "create", "settings"]) {
    f.nodes.set(`[data-testid="map-button-${name}"]`, {
      click: () => activated.push(name),
    })
  }
  const replay = new Element()
  replay.hidden = true
  f.nodes.set("[data-map-replay-panel]", replay)
  const opener = new Element()
  opener.click = () => {
    activated.push("replay-open")
    replay.hidden = false
  }
  f.nodes.set("[data-map-replay-open]", opener)
  const closer = new Element()
  closer.click = () => {
    activated.push("replay-close")
    replay.hidden = true
  }
  f.nodes.set("[data-map-replay-close]", closer)
  assert.equal(await f.owner.mount(), "ready")
  const key = (key, extra = {}) => ({
    key,
    preventDefault() {},
    target: { closest: () => null },
    ...extra,
  })
  for (const letter of ["t", "L", "/", "c", "s", "r", "r"])
    document.emit("keydown", key(letter))
  assert.deepEqual(activated, [
    "timeline",
    "layers",
    "search",
    "create",
    "settings",
    "replay-open",
    "replay-close",
  ])
  for (const extra of [
    { ctrlKey: true },
    { metaKey: true },
    { altKey: true },
    { repeat: true },
    { target: { closest: () => ({}) } },
  ]) {
    document.emit("keydown", key("t", extra))
  }
  assert.equal(activated.length, 7)
  f.owner.destroy()
  assert.equal(document.listeners.get("keydown").size, 0)
  document.emit("keydown", key("t"))
  assert.equal(activated.length, 7)
})
