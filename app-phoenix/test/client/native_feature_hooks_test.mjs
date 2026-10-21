import assert from "node:assert/strict"
import test from "node:test"
import { lazyFeature } from "../../assets/js/hooks/achievement_family.js"

function fixture() {
  let resolve
  const listeners = new Map(), calls = []
  const target = {}
  const hook = {
    ...lazyFeature("Feature", [["change", "change"]], () => new Promise((done) => { resolve = done })),
    el: { addEventListener: (type, fn) => listeners.set(type, fn), removeEventListener: (type) => listeners.delete(type), contains: (node) => node === target },
  }
  const module = { Feature: { mounted() { calls.push("mount") }, change(event) { calls.push(event.value) }, destroyed() { calls.push("destroy") } } }
  return { hook, listeners, calls, target, resolve: () => resolve(module) }
}

test("native feature hooks retain an input change while their lazy module loads", async () => {
  const { hook, listeners, calls, target, resolve } = fixture()
  const pending = hook.mounted()
  let prevented = false
  listeners.get("change")({ type: "change", target, value: "consent", preventDefault() { prevented = true } })
  resolve()
  await pending
  assert.equal(prevented, true)
  assert.deepEqual(calls, ["mount", "consent"])
  assert.equal(listeners.size, 0)
  hook.destroyed()
  assert.deepEqual(calls, ["mount", "consent", "destroy"])
})

test("departure before a native feature import resolves removes listeners and never mounts", async () => {
  const { hook, listeners, calls, resolve } = fixture()
  const pending = hook.mounted()
  hook.destroyed()
  resolve()
  await pending
  assert.equal(listeners.size, 0)
  assert.deepEqual(calls, [])
})
