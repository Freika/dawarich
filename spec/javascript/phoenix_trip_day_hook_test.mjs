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
    layers: { selectDay: (day) => selected.push(day) },
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

test("native trip day commands select only their map and unregister on destroy", async () => {
  const a = fixture(),
    b = fixture()
  a.release()
  b.release()
  await Promise.all([a.hook.mounted(), b.hook.mounted()])
  assert.equal(typeof a.handlers.get("trip:select_day"), "function")
  a.handlers.get("trip:select_day")({ day: "2026-10-01" })
  assert.deepEqual(a.selected, ["2026-10-01"])
  assert.deepEqual(b.selected, [])
  a.handlers.get("trip:select_day")({ day: null })
  assert.deepEqual(a.selected, ["2026-10-01", null])
  a.hook.destroyed()
  b.hook.destroyed()
  assert.ok(a.removed.includes("trip:select_day"))
  assert.equal(a.handlers.size, 0)
})

test("a trip day before map load applies once and stale commands after destroy are inert", async () => {
  const f = fixture()
  const mounting = f.hook.mounted()
  await f.started
  assert.equal(typeof f.handlers.get("trip:select_day"), "function")
  const late = f.handlers.get("trip:select_day")
  late({ day: "2026-10-02" })
  assert.deepEqual(f.selected, [])
  f.release()
  await mounting
  assert.deepEqual(f.selected, ["2026-10-02"])
  late({ day: "not-a-day" })
  assert.deepEqual(f.selected, ["2026-10-02"])
  f.hook.destroyed()
  late({ day: "2026-10-03" })
  assert.deepEqual(f.selected, ["2026-10-02"])
})

test("a trip day arriving at readiness is applied once", async () => {
  const f = fixture()
  let ready = false
  Object.defineProperty(f.hook, "mapReady", {
    get: () => ready,
    set(value) {
      ready = value
      if (value) f.handlers.get("trip:select_day")({ day: "2026-10-04" })
    },
  })
  f.release()
  await f.hook.mounted()
  assert.deepEqual(f.selected, ["2026-10-04"])
  f.hook.destroyed()
})

test("trip day receipts synchronize native details after the server patch", async () => {
  const f = fixture()
  const days = ["2026-10-01", "2026-10-02"].map((day) => ({
    id: `native-trip-day-${day}`,
    open: false,
  }))
  f.hook.el.closest = () => ({ querySelectorAll: () => days })
  f.release()
  await f.hook.mounted()
  const select = f.handlers.get("trip:select_day")
  select({ day: "2026-10-01" })
  assert.deepEqual(
    days.map((day) => day.open),
    [true, false],
  )
  select({ day: null, expanded: true })
  assert.deepEqual(
    days.map((day) => day.open),
    [true, true],
  )
  select({ day: null, expanded: false })
  assert.deepEqual(
    days.map((day) => day.open),
    [false, false],
  )
  f.hook.destroyed()
})
