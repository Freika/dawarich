import assert from "node:assert/strict"
import test from "node:test"
import { PublicMap } from "../../app-phoenix/assets/js/map/hooks/public_map.js"

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
    selectDay: (day) => selected.push(day),
    destroy() {},
    reconnect() {},
  }
  const hook = {
    ...PublicMap,
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

test("native public day commands select only their map and unregister on destroy", async () => {
  const a = fixture(),
    b = fixture()
  a.release()
  b.release()
  await Promise.all([a.hook.mounted(), b.hook.mounted()])
  assert.equal(typeof a.handlers.get("public:day"), "function")
  a.handlers.get("public:day")({ day: "2026-10-01" })
  assert.deepEqual(a.selected, ["2026-10-01"])
  assert.deepEqual(b.selected, [])
  a.handlers.get("public:day")({ day: null })
  assert.deepEqual(a.selected, ["2026-10-01", null])
  a.hook.destroyed()
  b.hook.destroyed()
  assert.ok(a.removed.includes("public:day"))
  assert.equal(a.handlers.size, 0)
})

test("a public day before map load applies once and stale commands after destroy are inert", async () => {
  const f = fixture()
  const mounting = f.hook.mounted()
  await f.started
  assert.equal(typeof f.handlers.get("public:day"), "function")
  const late = f.handlers.get("public:day")
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

test("a public day arriving at readiness is applied once", async () => {
  const f = fixture()
  let ready = false
  Object.defineProperty(f.hook, "mapReady", {
    get: () => ready,
    set(value) {
      ready = value
      if (value) f.handlers.get("public:day")({ day: "2026-10-04" })
    },
  })
  f.release()
  await f.hook.mounted()
  assert.deepEqual(f.selected, ["2026-10-04"])
  f.hook.destroyed()
})

test("public hover stays local to its map and leaving restores the selected day", async () => {
  const { bindPublicDays } = await import(
    "../../app-phoenix/assets/js/map/public/day_hover.js"
  )
  const roots = [new EventTarget(), new EventTarget()]
  const selected = [[], []]
  const stops = roots.map((root, i) =>
    bindPublicDays(root, {
      preview: (day) => selected[i].push(day),
      selected: () => "2026-10-01",
    }),
  )
  function hover(root, type, day, owner = root) {
    const row = { dataset: { publicDay: day }, closest: () => owner }
    const event = new Event(type)
    Object.defineProperty(event, "target", { value: { closest: () => row } })
    root.dispatchEvent(event)
  }
  hover(roots[0], "mouseover", "2026-10-02")
  hover(roots[0], "mouseover", "malformed")
  hover(roots[0], "mouseout", "2026-10-02")
  hover(roots[0], "mouseover", "2026-10-03", roots[1])
  assert.deepEqual(selected, [["2026-10-02", "2026-10-01"], []])
  stops.forEach((stop) => stop())
  hover(roots[0], "mouseover", "2026-10-03")
  assert.equal(selected[0].length, 2)
})
