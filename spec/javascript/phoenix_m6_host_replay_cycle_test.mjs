import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native replay cycles colocated minute points without creating another clock", async () => {
  const f = fixture()
  const controls = Object.fromEntries(
    [
      "play",
      "speed",
      "speedLabel",
      "prev",
      "next",
      "day",
      "dayCount",
      "time",
      "velocity",
      "noData",
      "follow",
      "scrubber",
      "cycle",
      "cyclePrev",
      "cycleNext",
      "cycleCount",
    ].map((key) => [key, new Element()]),
  )
  for (const [key, value] of Object.entries(controls))
    f.nodes.set(`[data-replay="${key}"]`, value)
  f.owner.source.snapshot = async () => ({
    points: [13, 14].map((longitude) => ({
      timestamp: 1774861200,
      longitude,
      latitude: 52,
    })),
  })
  await f.owner.mount()
  await f.owner.replay.open()
  assert.equal(controls.cycle.hidden, false)
  assert.equal(controls.cycleCount.textContent, "1 / 2")
  controls.cycleNext.emit("click")
  assert.equal(
    f.sources.get("native-replay-marker").data.geometry.coordinates[0],
    14,
  )
  assert.equal(controls.cycleCount.textContent, "2 / 2")
  controls.cyclePrev.emit("click")
  assert.equal(
    f.sources.get("native-replay-marker").data.geometry.coordinates[0],
    13,
  )
  f.owner.replay.close()
  assert.equal(controls.cycleNext.listeners.get("click").size, 0)
  f.owner.destroy()
})
