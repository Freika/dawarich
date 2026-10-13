import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/family_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const dependencies = `
  const translate = (key) => key;
  const maplibregl = { Popup: class { remove() { this.removed = true } } };
  class HtmlLabelManager {
    sync(features) { this.features = features }
    setVisibility(visible) { this.visible = visible }
    clear() { this.cleared = true }
    setFilter() {}
  }
  class BaseLayer {
    constructor(map, options) { this.map = map; this.id = options.id; }
    add(data) { this.data = data; }
    update(data) { this.data = data; }
    remove() { this.data = null; }
    setVisibility(visible) { this.visible = visible; }
  }
`
const { FamilyLayer } = await import(
  `data:text/javascript;base64,${Buffer.from(dependencies + source.replace(/^import .*\n/gm, "")).toString("base64")}`
)

for (const [name, expected] of [
  ["Ada Lovelace", "Ada Lovelace"],
  [undefined, "member@example.test"],
  ["", "member@example.test"],
]) {
  test(`initial and realtime family labels use ${JSON.stringify(expected)} for name ${JSON.stringify(name)}`, () => {
    const layer = new FamilyLayer({ getSource() {} })
    const member = {
      user_id: 1,
      email: "member@example.test",
      name,
      longitude: 13.4,
      latitude: 52.5,
    }
    layer.loadMembers([member])
    assert.equal(layer.data.features[0].properties.name, expected)
    layer.updateMember(member)
    assert.equal(layer.data.features[0].properties.name, expected)
  })
}

test("family labels and hover handlers both survive add and are released by remove", () => {
  const events = []
  const canvas = {
    style: {},
    addEventListener: (name) => events.push(`add:${name}`),
    removeEventListener: (name) => events.push(`remove:${name}`),
  }
  const map = {
    on: (name) => events.push(`on:${name}`),
    off: (name) => events.push(`off:${name}`),
    getCanvas: () => canvas,
  }
  const layer = new FamilyLayer(map)
  const data = { features: [{ properties: { id: 1, name: "🧑 Ada" } }] }
  layer.add(data)
  assert.equal(layer.labels.features, data.features)
  assert.equal(layer._hoverAttached, true)
  layer.setVisibility(false)
  assert.equal(layer.labels.visible, false)
  layer._popupVisible = true
  layer.remove()
  assert.equal(layer.labels.cleared, true)
  assert.equal(layer._popup.removed, true)
  assert.equal(layer._hoverAttached, false)
  assert.equal(events.filter((event) => event.startsWith("on:")).length, 3)
  assert.equal(events.filter((event) => event.startsWith("off:")).length, 3)
  assert.ok(events.includes("remove:mouseleave"))
})
