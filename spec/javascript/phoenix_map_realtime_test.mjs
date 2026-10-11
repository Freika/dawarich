import assert from "node:assert/strict"
import { test } from "node:test"
import { createRealtime } from "../../app-phoenix/assets/js/map/data/realtime.js"

function fixture(run = async () => "ready") {
  let next = 0
  const jobs = new Map()
  const timers = {
    setTimeout(fn) {
      jobs.set(++next, fn)
      return next
    },
    clearTimeout(id) {
      jobs.delete(id)
    },
  }
  const owner = createRealtime({ run, timers })
  return {
    owner,
    jobs,
    async flush() {
      const pending = [...jobs.values()]
      jobs.clear()
      for (const fn of pending) await fn()
      await Promise.resolve()
    },
  }
}
test("reconnect refreshes revision without replaying duplicate edits", async () => {
  let calls = 0
  const f = fixture(async () => {
    calls++
    return "ready"
  })
  const receipt = { kind: "map_edits", revision: 7, points: [[52, 13]] }
  f.owner.invalidate(receipt)
  f.owner.invalidate(receipt)
  await f.flush()
  assert.equal(calls, 1)
  f.owner.reconnect()
  await f.flush()
  assert.equal(calls, 2)
  assert.equal(await f.owner.invalidate(receipt), "ignored")
  assert.equal(f.jobs.size, 0)
  f.owner.destroy()
})
test("event bursts coalesce into one current and one follow-up read", async () => {
  let resolve,
    calls = 0
  const pending = new Promise((r) => {
    resolve = r
  })
  const f = fixture(() => {
    calls++
    return calls === 1 ? pending : Promise.resolve("ready")
  })
  f.owner.invalidate({ kind: "points", revision: 1 })
  f.owner.invalidate({ kind: "imports", revision: 1 })
  assert.equal(f.jobs.size, 1)
  const flush = f.flush()
  await Promise.resolve()
  f.owner.invalidate({ kind: "points", revision: 2 })
  f.owner.invalidate({ kind: "tracks", revision: 3 })
  assert.equal(calls, 1)
  resolve("ready")
  await flush
  await f.flush()
  assert.equal(calls, 2)
  f.owner.destroy()
})
test("destroy cancels queued reconciliation and ignores a late completion", async () => {
  let calls = 0
  const f = fixture(async () => {
    calls++
    return "ready"
  })
  const queued = f.owner.invalidate({ kind: "points", revision: 1 })
  f.owner.destroy()
  assert.equal(f.jobs.size, 0)
  assert.equal(await queued, "cancelled")
  await f.flush()
  assert.equal(calls, 0)
  assert.equal(f.jobs.size, 0)
  let resolve
  const g = fixture(
    () =>
      new Promise((r) => {
        resolve = r
      }),
  )
  const active = g.owner.reconnect()
  const flushing = g.flush()
  await Promise.resolve()
  g.owner.destroy()
  resolve("ready")
  await flushing
  assert.equal(await active, "cancelled")
  assert.equal(g.jobs.size, 0)
})
test("unrecognized or malformed revisions do not trigger reads", async () => {
  const f = fixture()
  for (const receipt of [
    { kind: "foreign", revision: 1 },
    { kind: "points", revision: -1 },
    { kind: "points", revision: NaN },
  ])
    assert.equal(await f.owner.invalidate(receipt), "ignored")
  assert.equal(f.jobs.size, 0)
  f.owner.destroy()
})

test("map hook owns coalesced delivery handlers and releases them on teardown", async () => {
  const { MapHook } = await import("../../app-phoenix/assets/js/hooks/map.js")
  const handlers = new Map(),
    removed = [],
    jobs = new Map()
  let timer = 0
  const clock = {
    setTimeout(fn) {
      jobs.set(++timer, fn)
      return timer
    },
    clearTimeout(id) {
      jobs.delete(id)
    },
  }
  const receipts = []
  let reads = 0,
    destroyed = 0
  const hook = {
    ...MapHook,
    mapTimers: clock,
    el: { dataset: {} },
    pushEvent() {},
    handleEvent(name, fn) {
      handlers.set(name, fn)
      return name
    },
    removeHandleEvent(ref) {
      removed.push(ref)
    },
    loader: async () => ({
      mountHost: () => ({
        async mount() {
          return "ready"
        },
        async reconnect(receipt) {
          receipts.push(receipt)
          reads++
          return "ready"
        },
        destroy() {
          destroyed++
        },
      }),
    }),
  }
  await hook.mounted()
  handlers.get("map:invalidate")({ kind: "points", revision: 1 })
  handlers.get("map:invalidate")({ kind: "points", revision: 1 })
  const reconnect = hook.reconnected()
  assert.equal(jobs.size, 1)
  const callbacks = [...jobs.values()]
  jobs.clear()
  for (const callback of callbacks) await callback()
  await reconnect
  assert.equal(reads, 1)
  assert.deepEqual(receipts, [{ kinds: ["points", "reconnect"] }])
  handlers.get("map:invalidate")({ kind: "points", revision: 2 })
  hook.destroyed()
  assert.equal(jobs.size, 0)
  assert.equal(reads, 1)
  assert.equal(destroyed, 1)
  assert.deepEqual([...handlers.keys()].sort(), [
    "enrichment:matches",
    "map:clear",
    "map:config",
    "map:invalidate",
    "map:layer",
    "map:settings",
    "place:focus",
    "track:selection",
    "visit:selection",
  ])
  assert.deepEqual([...removed].sort(), [...handlers.keys()].sort())
})

test("reconnect while the map chunk loads keeps a bounded invalidation queue", async () => {
  const { MapHook } = await import("../../app-phoenix/assets/js/hooks/map.js")
  let release
  const pending = new Promise((resolve) => {
      release = resolve
    }),
    jobs = new Map()
  let next = 0
  const hook = {
    ...MapHook,
    el: { dataset: {} },
    pushEvent() {},
    handleEvent: () => 0,
    removeHandleEvent() {},
    mapTimers: {
      setTimeout(fn) {
        jobs.set(++next, fn)
        return next
      },
      clearTimeout(id) {
        jobs.delete(id)
      },
    },
    loader: () => pending,
  }
  const mounting = hook.mounted()
  for (let n = 0; n < 128; n++) hook.reconnected()
  assert.ok(hook.mapInvalidations.length <= 32)
  release({
    mountHost: () => ({ async mount() {}, async reconnect() {}, destroy() {} }),
  })
  await mounting
  assert.equal(jobs.size, 1)
  hook.destroyed()
  assert.equal(jobs.size, 0)
})

test("native realtime batches retain only admitted invalidation kinds", async () => {
  const batches = [],
    f = fixture(async (receipt) => {
      batches.push(receipt)
      return "ready"
    })
  f.owner.invalidate({ kind: "family", revision: 1, secret: "discard" })
  f.owner.invalidate({ kind: "points", revision: 1 })
  f.owner.invalidate({ kind: "points", revision: 1 })
  await f.flush()
  assert.deepEqual(batches, [{ kinds: ["family", "points"] }])
  f.owner.reconnect()
  await f.flush()
  assert.deepEqual(batches[1], { kinds: ["reconnect"] })
  f.owner.destroy()
})

test("native realtime rejects unknown kinds without a revision", async () => {
  const f = fixture()
  assert.equal(await f.owner.invalidate({ kind: "unknown" }), "ignored")
  assert.equal(f.jobs.size, 0)
  f.owner.destroy()
})
