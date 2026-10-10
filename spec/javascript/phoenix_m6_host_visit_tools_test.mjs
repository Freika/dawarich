import assert from "node:assert/strict"
import test from "node:test"
import { fixture, Element } from "./support/native_m6_host_fixture.mjs"

test("native map host creates visits and routes tile point addresses", async () => {
  const f = fixture()
  const button = new Element()
  f.nodes.set('[data-testid="native-create-visit"]', button)
  await f.owner.mount()
  button.emit("click")
  f.map.emit("click", {lngLat: {lat: 52, lng: 13}})
  assert.equal(f.pushed.some(item => item.event === "visit:new"), true)
  f.map.emit("click:points-mvt", {features: [{properties: {id: 7}}]})
  assert.deepEqual(f.pushed.find(item => item.event === "address:open").payload, {id: 7})
  f.owner.destroy()
  assert.equal(f.listeners.get("click:points-mvt").size, 0)
})
