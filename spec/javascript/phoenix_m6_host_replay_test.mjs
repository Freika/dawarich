import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native map replay consumes its scoped source and releases markers on close", async () => {
  const f = fixture()
  await f.owner.mount()
  let calls = 0
  f.owner.source.snapshot = async ({ purpose }) => {
    assert.equal(purpose, "replay")
    calls++
    return {
      points: [{ timestamp: 1774861200, longitude: 13, latitude: 52 }],
      photos: [],
    }
  }
  await f.owner.replay.open(f.owner.config.range)
  assert.equal(calls, 1)
  assert.equal(f.sources.has("native-replay-marker"), true)
  f.owner.replay.close()
  assert.equal(f.sources.has("native-replay-marker"), false)
  await f.owner.replay.open(f.owner.config.range)
  f.owner.destroy()
  assert.equal(f.sources.has("native-replay-marker"), false)
})

test("native replay replaces its profile clock when the range timezone changes", async () => {
  const f = fixture()
  await f.owner.mount()
  f.owner.source.snapshot = async () => ({
    points: [
      {
        timestamp: Date.parse("2026-03-29T22:30:00Z") / 1000,
        longitude: 13,
        latitude: 52,
      },
    ],
  })
  await f.owner.replay.open()
  assert.equal(f.owner.replay.manager.getCurrentDay(), "2026-03-30")
  await f.owner.update({
    ...f.owner.config,
    revision: 2,
    range: { ...f.owner.config.range, timezone: "UTC" },
  })
  assert.equal(f.owner.replay.manager.getCurrentDay(), "2026-03-29")
  assert.equal(f.owner.replay.manager.getCurrentDayLengthMinutes(), 1440)
  f.owner.destroy()
})
