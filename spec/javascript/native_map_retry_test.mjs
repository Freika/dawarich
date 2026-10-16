import assert from "node:assert/strict"
import { test } from "node:test"
import { createMapRetry } from "../../app-phoenix/assets/js/map/ui/retry.js"

function fixture() {
  const nodes = []
  const document = { createElement: () => {
    const node = { style: {}, dataset: {}, children: [], listeners: {}, setAttribute(key, value) { this[key] = value }, append(...items) { this.children.push(...items) }, addEventListener(key, fn) { this.listeners[key] = fn }, remove() { this.removed = true } }
    nodes.push(node)
    return node
  } }
  const root = { ownerDocument: document, append(node) { this.node = node } }
  return { root, nodes }
}

test("native map failures expose one bounded retry and perform the failed read again", async () => {
  const { root } = fixture()
  const calls = []
  const retry = createMapRetry({ root, translate: key => key, run: async code => calls.push(code) })
  retry.fail("point_tiles_failed")
  retry.fail("point_tiles_failed")
  assert.equal(root.node?.role, "alert")
  assert.equal(root.node.style.pointerEvents, "none")
  assert.match(root.node.style.overflowWrap, /anywhere/)
  const button = root.node.children[1]
  assert.equal(button.style.pointerEvents, "auto")
  await button.listeners.click()
  assert.deepEqual(calls, ["point_tiles_failed"])
  assert.equal(root.node.removed, true)
})

test("native retry retains a failed read and retires listeners on teardown", async () => {
  const { root } = fixture()
  let calls = 0
  const retry = createMapRetry({ root, translate: key => key, run: async () => { calls++; throw new Error("unavailable") } })
  retry.fail("scratch_tiles_failed")
  const button = root.node?.children[1]
  assert.ok(button)
  await button.listeners.click()
  assert.equal(root.node.removed, undefined)
  assert.equal(button.disabled, false)
  retry.destroy()
  await button.listeners.click()
  assert.equal(calls, 1)
  assert.equal(root.node.removed, true)
})
