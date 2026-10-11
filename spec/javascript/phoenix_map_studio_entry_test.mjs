import assert from "node:assert/strict"
import { test } from "node:test"
import { MapHook } from "../../app-phoenix/assets/js/hooks/map.js"
import { installStudios } from "../../app-phoenix/assets/js/map/ui/studios.js"

test("native hub studio entry waits for the owned map before opening", async () => {
  let ready
  const mounting = new Promise((resolve) => { ready = resolve })
  const opened = []
  const owner = {
    config: {},
    mount: () => mounting,
    openStudio: (kind) => opened.push(kind),
    destroy() {},
  }
  const hook = {
    ...MapHook,
    el: { ownerDocument: { location: { href: "https://example.test/map/v2?studio=video" } } },
    loader: async () => ({ mountHost: () => owner }),
    handleEvent: () => 1,
    removeHandleEvent() {},
    pushEvent() {},
  }
  const mounted = hook.mounted()
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(opened, [])
  ready("ready")
  await mounted
  assert.deepEqual(opened, ["video"])
  hook.destroyed()
})

test("owned studio entry validates its kind and expires on host destruction", () => {
  const opened = []
  const listeners = new Map()
  const root = {
    querySelector: (selector) => selector.includes("studio") ? {
      dispatchEvent: (event) => opened.push({ selector, event }),
    } : null,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
  }
  const cleanups = []
  const owner = { source: {}, map: { getBounds: () => null } }
  installStudios({ element: { closest: () => root }, owner, lifetime: { own: (fn) => cleanups.push(fn) } })
  owner.openStudio("unknown")
  assert.equal(opened.length, 0)
  owner.openStudio("video")
  assert.equal(opened[0].event.type, "dawarich:video-studio-open")
  assert.equal(opened[0].event.detail.source, owner.source)
  owner.openStudio("poster")
  assert.equal(opened[1].event.type, "dawarich:poster-studio-open")
  assert.equal(opened[1].event.detail.source, owner.source)
  for (const cleanup of cleanups.reverse()) cleanup()
  assert.equal(owner.openStudio, undefined)
  assert.equal(listeners.size, 0)
})
