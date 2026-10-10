import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native map host replay binds day scrubber and speed then unbinds panel on close", async () => {
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
    ].map((key) => [key, new Element()]),
  )
  for (const [key, control] of Object.entries(controls))
    f.nodes.set(`[data-replay="${key}"]`, control)
  await f.owner.mount()
  f.owner.source.snapshot = async () => ({
    points: [
      { timestamp: 1774861200, longitude: 13, latitude: 52 },
      { timestamp: 1774947600, longitude: 14, latitude: 53 },
    ],
  })
  await f.owner.replay.open()
  assert.ok(controls.day.textContent)
  controls.next.emit("click")
  assert.equal(f.owner.replay.manager.currentDayIndex, 1)
  controls.scrubber.value = "500"
  controls.scrubber.emit("input")
  assert.ok(controls.time.textContent)
  controls.speed.value = "4"
  controls.speed.emit("input")
  assert.equal(controls.speedLabel.textContent, "10x")
  f.owner.replay.close()
  assert.equal(controls.next.listeners.get("click").size, 0)
  assert.equal(controls.scrubber.listeners.get("input").size, 0)
  f.owner.destroy()
})
