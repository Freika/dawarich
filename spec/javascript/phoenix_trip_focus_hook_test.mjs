import assert from "node:assert/strict"
import test from "node:test"
import { TripHook } from "../../app-phoenix/assets/js/map/hooks/trip.js"

function fixture() {
  const handlers = new Map(),
    selected = [],
    removed = []
  let release, entered
  const gate = new Promise((resolve) => {
    release = resolve
  })
  const started = new Promise((resolve) => {
    entered = resolve
  })
  const owner = {
    config: {},
    mount: async () => {
      entered()
      await gate
    },
    layers: {
      focusPlan: (longitude, latitude) => selected.push([longitude, latitude]),
    },
    destroy() {},
    reconnect() {},
  }
  const hook = {
    ...TripHook,
    el: { dataset: {} },
    loader: async () => ({ mountHost: () => owner }),
    handleEvent(name, handler) {
      handlers.set(name, handler)
      return name
    },
    removeHandleEvent(ref) {
      removed.push(ref)
      handlers.delete(ref)
    },
    pushEvent() {},
  }
  return { hook, handlers, selected, removed, release, started }
}

test("native itinerary focus commands affect only their map and unregister on destroy", async () => {
  const a = fixture(),
    b = fixture()
  a.release()
  b.release()
  await Promise.all([a.hook.mounted(), b.hook.mounted()])
  assert.equal(typeof a.handlers.get("trip:focus"), "function")
  a.handlers.get("trip:focus")({ longitude: 13.4, latitude: 52.5 })
  assert.deepEqual(a.selected, [[13.4, 52.5]])
  assert.deepEqual(b.selected, [])
  a.handlers.get("trip:focus")({ longitude: 12.3, latitude: 51.2 })
  assert.deepEqual(a.selected, [
    [13.4, 52.5],
    [12.3, 51.2],
  ])
  a.hook.destroyed()
  b.hook.destroyed()
  assert.ok(a.removed.includes("trip:focus"))
  assert.equal(a.handlers.size, 0)
})

test("an itinerary focus before map load applies once and stale commands after destroy are inert", async () => {
  const f = fixture()
  const mounting = f.hook.mounted()
  await f.started
  assert.equal(typeof f.handlers.get("trip:focus"), "function")
  const late = f.handlers.get("trip:focus")
  late({ longitude: 13.4, latitude: 52.5 })
  assert.deepEqual(f.selected, [])
  f.release()
  await mounting
  assert.deepEqual(f.selected, [[13.4, 52.5]])
  late({ longitude: 181, latitude: 52.5 })
  assert.deepEqual(f.selected, [[13.4, 52.5]])
  f.hook.destroyed()
  late({ longitude: 12.3, latitude: 51.2 })
  assert.deepEqual(f.selected, [[13.4, 52.5]])
})

test("an itinerary focus arriving at readiness is applied once", async () => {
  const f = fixture()
  let ready = false
  Object.defineProperty(f.hook, "mapReady", {
    get: () => ready,
    set(value) {
      ready = value
      if (value)
        f.handlers.get("trip:focus")({ longitude: 13.4, latitude: 52.5 })
    },
  })
  f.release()
  await f.hook.mounted()
  assert.deepEqual(f.selected, [[13.4, 52.5]])
  f.hook.destroyed()
})
