import assert from "node:assert/strict"
import test from "node:test"
import { waitForStyle } from "../../app-phoenix/assets/js/map/runtime/style_ready.js"

test("already loaded native style admits geometry while basemap tiles remain pending", async () => {
  let admitted = false
  const listeners = []
  const map = {
    loaded: () => false,
    isStyleLoaded: () => true,
    once: (name) => listeners.push(name),
    off() {},
  }
  waitForStyle(map, { own() {} }).then(() => { admitted = true })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(admitted, true)
  assert.deepEqual(listeners, [])
})
