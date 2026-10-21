import assert from "node:assert/strict"
import test from "node:test"
import { createReplayDensity } from "../../app-phoenix/assets/js/map/replay/density.js"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"
import { Element } from "./support/native_m6_host_fixture.mjs"

test("native replay density renders the Rails profile-day bars and clears on destroy", () => {
  const manager = new ReplayManager({ timezone: "Europe/Berlin" })
  manager.setPoints([{ timestamp: 1774746000, longitude: 13, latitude: 52 }])
  const container = new Element(),
    document = { createElement: () => new Element() }
  const strip = createReplayDensity({ container, document, manager })
  assert.equal(container.children.length, 48)
  assert.ok(
    container.children.every((bar) =>
      bar.className.startsWith("replay-density-bar"),
    ),
  )
  const filled = container.children.filter((bar) =>
    bar.classList.contains("has-data"),
  )
  assert.equal(filled.length, 1)
  assert.ok(filled[0].classList.contains("high-density"))
  strip.destroy()
  assert.deepEqual(container.children, [])
})
