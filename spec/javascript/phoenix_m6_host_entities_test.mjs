import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native map host arms place creation and enables its owned entity layer", async () => {
  const f = fixture()
  const button = new Element()
  f.nodes.set('[data-testid="native-create-place"]', button)
  await f.owner.mount()
  button.emit("click")
  f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
  assert.deepEqual(
    f.pushed.find((item) => item.event === "place:new").payload,
    { latitude: 52, longitude: 13 },
  )
  await f.owner.layer({ layer: "places", enabled: true })
  assert.equal(f.owner.config.placesEnabled, true)
  assert.equal(
    f.reads.some((item) => item.resource === "places"),
    true,
  )
  f.owner.destroy()
  assert.equal(button.listeners.get("click").size, 0)
})
