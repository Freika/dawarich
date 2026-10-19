import assert from "node:assert/strict"
import test from "node:test"
import { createRealtime } from "../../assets/js/map/data/realtime.js"
import { createMapFamilyLayer } from "../../assets/js/map/family/host.js"
import { installRealtimeActions } from "../../assets/js/map/runtime/realtime_actions.js"

function fakeTimers() {
  let now = 0,
    next = 1
  const pending = new Map()
  return {
    now: () => now,
    setTimeout(fn, delay = 0) {
      const id = next++
      pending.set(id, { fn, at: now + delay })
      return id
    },
    clearTimeout(id) {
      pending.delete(id)
    },
    setInterval() {
      throw new Error("no polling")
    },
    clearInterval() {},
    async advance(ms) {
      const until = now + ms
      for (;;) {
        const due = [...pending]
          .filter(([, t]) => t.at <= until)
          .sort((a, b) => a[1].at - b[1].at)[0]
        if (!due) break
        pending.delete(due[0])
        now = due[1].at
        await due[1].fn()
        await Promise.resolve()
      }
      now = until
    },
  }
}

function fakeDocument(state = "visible") {
  const listeners = []
  return {
    get visibilityState() {
      return state
    },
    addEventListener(name, fn) {
      if (name === "visibilitychange") listeners.push(fn)
    },
    removeEventListener() {},
    show() {
      state = "visible"
      for (const fn of listeners) fn()
    },
  }
}

test("a burst of track updates runs one refresh one second after the first", async () => {
  const timers = fakeTimers(),
    runs = []
  const realtime = createRealtime({
    run: (batch) => runs.push(batch),
    timers,
    document: fakeDocument(),
  })
  for (let n = 1; n <= 30; n++)
    realtime.invalidate({ kind: "tracks", revision: n })
  await timers.advance(999)
  assert.equal(runs.length, 0)
  await timers.advance(1)
  assert.deepEqual(runs, [{ kinds: ["tracks"] }])
})

test("a map edit does not wait behind a pending track refresh", async () => {
  const timers = fakeTimers(),
    runs = []
  const realtime = createRealtime({
    run: (batch) => runs.push(batch),
    timers,
    document: fakeDocument(),
  })
  realtime.invalidate({ kind: "tracks", revision: 1 })
  realtime.invalidate({ kind: "map_edits", revision: 1 })
  await timers.advance(0)
  assert.deepEqual(runs, [{ kinds: ["tracks", "map_edits"] }])
})

test("a hidden tab defers every refresh until it becomes visible", async () => {
  const timers = fakeTimers(),
    runs = [],
    document = fakeDocument("hidden")
  const realtime = createRealtime({
    run: (batch) => runs.push(batch),
    timers,
    document,
  })
  for (let n = 1; n <= 10; n++)
    realtime.invalidate({ kind: "points", revision: n })
  realtime.invalidate({ kind: "tracks", revision: 1 })
  await timers.advance(60000)
  assert.equal(runs.length, 0)
  document.show()
  await timers.advance(1000)
  assert.deepEqual(runs, [{ kinds: ["points", "tracks"] }])
})

function owner(log) {
  const parts = {
    layers: {
      points: { refresh: () => log.push("points") },
      tracks: { refresh: () => log.push("tracks") },
    },
    density: {
      invalidate: () => log.push("density.invalidate"),
      update: async () => log.push("density.update"),
    },
    family: { update: async () => log.push("family") },
    recent: {
      prepare: () => log.push("recent.prepare"),
      deliver: async () => log.push("recent.deliver"),
    },
    editing: { reconcile: async () => log.push("edit.reconcile") },
    editor: { reapplyTileFilters: () => log.push("edit.filters") },
  }
  const target = {
    config: {},
    reconnect: async () => {
      log.push("full")
      return "ready"
    },
  }
  installRealtimeActions(target, () => parts)
  return target
}

test("track updates refresh only the track tiles", async () => {
  const log = []
  await owner(log).reconnect({ kinds: ["tracks"] })
  assert.deepEqual(log, ["tracks"])
})

test("new points refresh point tiles, visited countries and the recent point", async () => {
  const log = []
  await owner(log).reconnect({ kinds: ["points"] })
  assert.deepEqual(log, [
    "recent.prepare",
    "points",
    "density.invalidate",
    "density.update",
    "recent.deliver",
  ])
})

test("family updates reload family locations only", async () => {
  const log = []
  await owner(log).reconnect({ kinds: ["family"] })
  assert.deepEqual(log, ["family"])
})

test("import and notification progress never refresh the map", async () => {
  const log = []
  await owner(log).reconnect({ kinds: ["imports", "progress", "sharing"] })
  assert.deepEqual(log, [])
})

test("reconnects and local resource changes keep the full refresh", async () => {
  for (const kinds of [
    ["reconnect"],
    ["map"],
    ["map_edits"],
    ["tracks", "reconnect"],
    [],
  ]) {
    const log = []
    await owner(log).reconnect({ kinds })
    assert.deepEqual(log, ["full"])
  }
})

test("the family layer loads on update and never polls", async () => {
  const timers = fakeTimers(),
    reads = []
  const reader = {
    read: async (name) => {
      reads.push(name)
      return {
        data: name === "family_locations" ? { locations: [] } : { members: [] },
      }
    },
  }
  const overlay = { replace() {}, clear() {}, destroy() {} }
  const layer = createMapFamilyLayer({
    map: {},
    reader,
    library: {},
    root: null,
    timers,
    createOverlay: () => overlay,
  })
  await layer.update({
    familyEnabled: true,
    locale: "en",
    range: { startAt: "a", endAt: "b" },
  })
  await timers.advance(120000)
  assert.deepEqual(reads, ["family_locations", "family_history"])
  layer.destroy()
})
