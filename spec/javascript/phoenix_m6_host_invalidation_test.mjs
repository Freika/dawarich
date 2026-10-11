import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host same-range invalidation reloads both owned tile sources without replacing the map", async () => {
  const f = fixture({ tracksEnabled: true })
  const calls = []
  f.map.refreshTiles = (id) => calls.push(id)
  await f.owner.mount()
  assert.equal(f.owner.state, "ready")
  assert.deepEqual(calls, [])
  assert.equal(await f.owner.reconnect(), "ready")
  f.map.emit("render")
  assert.deepEqual(calls.sort(), ["points-mvt-source", "tracks-mvt-source"])
  assert.equal(f.owner.map, f.map)
  assert.equal(f.owner.config.range.startAt, "2026-03-29T00:00")
  calls.length = 0
  f.owner.destroy()
  assert.equal(await f.owner.reconnect(), "cancelled")
  assert.deepEqual(calls, [])
})
