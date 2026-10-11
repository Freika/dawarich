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

test("native creation guidance belongs to the armed tool and clears after click Escape and destroy", async () => {
  const f = fixture(),
    status = new Element(),
    visit = new Element(),
    area = new Element()
  status.dataset.visitMessage = "Localized visit placement"
  f.nodes.set("[data-map-tool-status]", status)
  f.nodes.set('[data-testid="native-create-visit"]', visit)
  f.nodes.set('[data-testid="native-create-area"]', area)
  try {
    await f.owner.mount()
    visit.emit("click")
    assert.equal(status.textContent, "Localized visit placement")
    f.root.emit("keydown", { key: "Escape" })
    f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
    assert.equal(
      f.pushed.some((item) => item.event === "visit:new"),
      false,
    )
    assert.equal(status.textContent, "")
    visit.emit("click")
    area.emit("click")
    f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
    assert.equal(
      f.pushed.some((item) => item.event === "visit:new"),
      false,
    )
    assert.equal(f.pushed.filter((item) => item.event === "area:new").length, 1)
    visit.emit("click")
    f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
    assert.equal(status.textContent, "")
    visit.emit("click")
    f.owner.destroy()
    assert.equal(status.textContent, "")
    assert.equal(f.root.listeners.get("keydown").size, 0)
  } finally {
    f.owner.destroy()
  }
})
