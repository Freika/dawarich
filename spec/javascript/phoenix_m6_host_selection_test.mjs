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
  assert.equal(f.root.listeners.get("click").size, 0)
})

test("native selection root draws rectangle highlights admitted points and clears on cancel", async () => {
  const f = fixture(),
    button = new Element(),
    status = new Element(),
    panel = new Element()
  const label = { textContent: "Select Area" }
  button.childNodes = [label]
  button.children = [label]
  button.ownerDocument = { createTextNode: (text) => ({ textContent: text }) }
  button.dataset.mapCancelMessage = "Cancel Selection"
  button.dataset.mapDrawMessage = "Draw a rectangle"
  f.nodes.set('[data-testid="native-select-area"]', button)
  f.nodes.set("[data-map-tool-status]", status)
  f.nodes.set("[data-map-selection]", panel)
  f.reader.pages = async () => [
    { id: 7, latitude: 52, longitude: 13, anomaly: true },
  ]
  f.reader.read = async () => ({ data: [] })
  f.map.unproject = ([lng, lat]) => ({ lng, lat })
  try {
    await f.owner.mount()
    button.emit("click")
    assert.match(button.innerHTML, /<line x1="18"/)
    assert.equal(button.children.at(-1).textContent.trim(), "Cancel Selection")
    assert.equal(status.textContent ?? "", "")
    f.map.emit("mousedown", { point: { x: 1, y: 2 } })
    f.map.emit("mousemove", { point: { x: 3, y: 4 } })
    assert.deepEqual(
      f.sources.get("selection-source").data.features[0].geometry
        .coordinates[0],
      [
        [1, 2],
        [3, 2],
        [3, 4],
        [1, 4],
        [1, 2],
      ],
    )
    f.map.emit("mouseup", { point: { x: 3, y: 4 } })
    await f.owner.selection.ready
    assert.deepEqual(
      f.sources.get("selected-points-source").data.features[0].geometry
        .coordinates,
      [13, 52],
    )
    assert.equal(
      f.sources.get("selected-points-source").data.features[0].properties.id,
      7,
    )
    assert.equal(
      f.layers.get("selected-points").paint["circle-color"],
      "#ef4444",
    )
    button.emit("click")
    assert.deepEqual(button.children, [label])
    assert.equal(status.textContent ?? "", "")
    assert.equal(f.sources.has("selection-source"), false)
    assert.equal(f.sources.has("selected-points-source"), false)
    assert.equal(f.map.dragPan.isEnabled(), true)
    assert.equal(panel.classList.contains("hidden"), true)
  } finally {
    f.owner.destroy()
  }
})
test("native selection disposal removes drawings and obsolete reads cannot redraw", async () => {
  const f = fixture(),
    button = new Element()
  f.nodes.set('[data-testid="native-select-area"]', button)
  let release
  f.reader.pages = () =>
    new Promise((resolve) => {
      release = resolve
    })
  f.reader.read = async () => ({ data: [] })
  f.map.unproject = ([lng, lat]) => ({ lng, lat })
  try {
    await f.owner.mount()
    button.emit("click")
    f.map.emit("mousedown", { point: { x: 1, y: 2 } })
    f.map.emit("mousemove", { point: { x: 3, y: 4 } })
    assert.equal(f.sources.has("selection-source"), true)
    f.map.emit("mouseup", { point: { x: 3, y: 4 } })
    f.owner.destroy()
    release([{ id: 7, latitude: 52, longitude: 13 }])
    await f.owner.selection.ready
    assert.deepEqual(f.owner.selection.state.points, [])
    assert.equal(f.sources.has("selection-source"), false)
    assert.equal(f.sources.has("selected-points-source"), false)
    assert.equal(f.root.listeners.get("keydown").size, 0)
  } finally {
    f.owner.destroy()
  }
})
