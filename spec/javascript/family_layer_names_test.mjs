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
  const maplibregl = { Popup: class {} };
  class BaseLayer {
    constructor(map, options) { this.map = map; this.id = options.id; }
    update(data) { this.data = data; }
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
