import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

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

test("native replay remains active while reopening other panels and refreshes a changed range", async () => {
  const f = fixture()
  await f.owner.mount()
  let reads = 0
  f.owner.source.snapshot = async () => {
    reads++
    return { points: [{ timestamp: 1774861200, longitude: 13, latitude: 52 }] }
  }
  try {
    await f.owner.replay.open()
    f.owner.replay.seek(321)
    const manager = f.owner.replay.manager
    const marker = structuredClone(f.sources.get("native-replay-marker").data)
    for (const panel of ["timeline", "layers", "settings", ""]) {
      await f.owner.update({ ...f.owner.config, panel })
      assert.equal(f.owner.replay.active, true)
      assert.equal(f.owner.replay.manager, manager)
      assert.deepEqual(f.sources.get("native-replay-marker").data, marker)
      assert.equal(reads, 1)
    }
    await f.owner.update({
      ...f.owner.config,
      revision: 2,
      panel: "timeline",
      range: { ...f.owner.config.range, endAt: "2026-03-30T23:59" },
    })
    assert.equal(f.owner.replay.active, true)
    assert.equal(reads, 2)
  } finally {
    f.owner.destroy()
  }
})

test("native replay opener toggles pending and ready runs without late marker leaks", async () => {
  const f = fixture()
  const opener = new Element()
  f.nodes.set("[data-map-replay-open]", opener)
  assert.equal(await f.owner.mount(), "ready")
  let release
  const pending = new Promise((resolve) => {
    release = resolve
  })
  f.owner.source.snapshot = () => pending
  try {
    opener.emit("click")
    assert.equal(f.owner.replay.active, true)
    opener.emit("click")
    assert.equal(f.owner.replay.active, false)
    release({
      points: [{ timestamp: 1774861200, longitude: 13, latitude: 52 }],
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.sources.has("native-replay-marker"), false)
    assert.equal(await f.owner.replay.open(), "ready")
    assert.equal(f.sources.has("native-replay-marker"), true)
    opener.emit("click")
    assert.equal(f.owner.replay.active, false)
    assert.equal(f.sources.has("native-replay-marker"), false)
  } finally {
    release({ points: [] })
    f.owner.destroy()
  }
})
