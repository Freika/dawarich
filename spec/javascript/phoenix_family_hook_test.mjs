import assert from "node:assert/strict"
import { test } from "node:test"
import { FamilyHook } from "../../app-phoenix/assets/js/map/hooks/family.js"

test("family hook clear before lazy import prevents allocation and releases handlers", async () => {
  let resolve,
    allocations = 0
  const loading = new Promise((r) => {
    resolve = r
  })
  const handlers = new Map(),
    removed = []
  const hook = {
    ...FamilyHook,
    el: { dataset: {} },
    loader: () => loading,
    handleEvent(name, fn) {
      handlers.set(name, fn)
      return name
    },
    removeHandleEvent(ref) {
      removed.push(ref)
    },
    pushEvent() {},
  }
  const pending = hook.mounted()
  handlers.get("map:clear")()
  resolve({
    mountHost() {
      allocations++
    },
  })
  await pending
  hook.destroyed()
  assert.equal(allocations, 0)
  assert.deepEqual([...handlers.keys()].sort(), [
    "enrichment:matches",
    "family:clear",
    "family:lease",
    "map:clear",
    "map:config",
    "map:invalidate",
    "map:layer",
    "map:settings",
    "track:selection",
    "visit:selection",
  ])
  assert.deepEqual([...removed].sort(), [...handlers.keys()].sort())
})

test("Family hook relays the latest server lease after lazy mount and clears an idle owner", async () => {
  let release
  const loaded = new Promise((resolve) => {
      release = resolve
    }),
    handlers = new Map(),
    leases = [],
    removed = []
  let cleared = 0
  const hook = {
    ...FamilyHook,
    el: { dataset: {} },
    loader: () => loaded,
    handleEvent(name, fn) {
      handlers.set(name, fn)
      return name
    },
    removeHandleEvent: (ref) => removed.push(ref),
    pushEvent() {},
  }
  const mounting = hook.mounted()
  try {
    assert.equal(typeof handlers.get("family:lease"), "function")
    handlers.get("family:lease")({ milliseconds: 1000 })
    handlers.get("family:lease")({ milliseconds: 500 })
    release({
      mountHost: () => ({
        mount: async () => "ready",
        lease: (receipt) => leases.push(receipt),
        clear: () => cleared++,
        destroy() {},
      }),
    })
    await mounting
    assert.deepEqual(leases, [{ milliseconds: 500 }])
    handlers.get("family:clear")({ code: "consent_expired" })
    assert.equal(cleared, 1)
    handlers.get("family:lease")({ milliseconds: 30000 })
    assert.deepEqual(leases.at(-1), { milliseconds: 30000 })
  } finally {
    release({ mountHost: () => ({ mount: async () => "ready", destroy() {} }) })
    await mounting
    hook.destroyed()
  }
  assert.ok(removed.includes("family:lease"))
  assert.ok(removed.includes("family:clear"))
})
