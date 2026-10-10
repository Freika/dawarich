import assert from "node:assert/strict"
import { test } from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("map host create-area tool owns its click and releases it on destroy", async () => {
  const f = fixture()
  const button = new Element()
  f.nodes.set('[data-testid="native-create-area"]', button)
  try {
    assert.equal(await f.owner.mount(), "ready")
    button.emit("click")
    f.map.emit("click", { lngLat: { lat: 52.52, lng: 13.405 } })
    assert.ok(
      f.pushed.some(
        ({ event, payload }) =>
          event === "area:new" && payload.latitude === 52.52,
      ),
    )
    button.emit("click")
    f.owner.destroy()
    f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
    assert.equal(f.pushed.filter(({ event }) => event === "area:new").length, 1)
    assert.equal(button.listeners.get("click")?.size ?? 0, 0)
  } finally {
    f.owner.destroy()
  }
})
