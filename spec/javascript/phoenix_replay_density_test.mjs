import assert from "node:assert/strict"
import test from "node:test"
import { createReplayDensity } from "../../app-phoenix/assets/js/map/replay/density.js"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"
import { Element } from "./support/native_m6_host_fixture.mjs"

test("native replay density preserves profile-day buckets and releases seek listeners", () => {
  const manager = new ReplayManager({ timezone: "Europe/Berlin" })
  manager.setPoints([{ timestamp: 1774746000, longitude: 13, latitude: 52 }])
  const container = new Element(),
    document = { createElement: () => new Element() },
    sought = []
  const strip = createReplayDensity({
    container,
    document,
    manager,
    seek: (value) => sought.push(value),
  })
  assert.equal(container.children.length, 48)
  assert.equal(
    container.children.some((bar) => bar.dataset.density !== "0"),
    true,
  )
  const bar = container.children[2]
  bar.emit("click")
  assert.equal(
    sought[0],
    Math.floor((manager.getCurrentDayLengthMinutes() * 2) / 48),
  )
  strip.destroy()
  bar.emit("click")
  assert.equal(sought.length, 1)
  assert.deepEqual(container.children, [])
})
