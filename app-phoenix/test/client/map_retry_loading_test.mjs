import assert from "node:assert/strict"
import test from "node:test"
import { installMapRetry } from "../../assets/js/map/runtime/retry.js"

test("retry UI loads only after failure and destroy refuses a pending load", async () => {
  let loads = 0, creations = 0, release
  const failures = [], destroyed = []
  const loader = () => { loads++; return new Promise(resolve => { release = resolve }) }
  const owner = { config: {}, destroy() { destroyed.push("owner") } }
  const retry = installMapRetry({ owner, loader })
  assert.equal(loads, 0)
  const pending = retry.fail("point_tiles_failed")
  const next = retry.fail("track_tiles_failed")
  assert.equal(loads, 1)
  owner.destroy()
  release({ createMapRetry: () => { creations++; return { fail() {} } } })
  await Promise.all([pending, next])
  assert.equal(creations, 0)
  assert.deepEqual(destroyed, ["owner"])
  assert.deepEqual(failures, [])
})

test("lazy retry replays failures once and retains point track and membership recovery", async () => {
  let loads = 0, cleanup = 0
  const failures = [], runs = []
  let run
  const owner = { config: {}, destroy() {}, reconnect: receipt => runs.push(receipt.kinds[0]) }
  const retry = installMapRetry({
    owner,
    layers: () => ({ points: { retry: () => runs.push("point") }, tracks: { retry: () => runs.push("track") } }),
    density: () => ({ retry: code => runs.push(code) }),
    loader: async () => { loads++; return { createMapRetry: options => {
      run = options.run
      return { fail: code => failures.push(code), destroy: () => cleanup++ }
    } } },
  })
  assert.equal(loads, 0)
  await Promise.all([retry.fail("point_tiles_failed"), retry.fail("track_tiles_failed")])
  assert.equal(loads, 1)
  assert.deepEqual(failures, ["point_tiles_failed", "track_tiles_failed"])
  for (const code of ["point_tiles_failed", "track_tiles_failed", "scratch_metadata_failed", "read_failed"]) await run(code)
  assert.deepEqual(runs, ["point", "track", "scratch_metadata_failed", "retry"])
  owner.destroy()
  assert.equal(cleanup, 1)
})
