import assert from "node:assert/strict"
import { test } from "node:test"
import { FamilyHook } from "../../app-phoenix/assets/js/hooks/family.js"

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
  assert.equal(removed.length, 3)
})
