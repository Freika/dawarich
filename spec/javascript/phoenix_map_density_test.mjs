import assert from "node:assert/strict"
import { test } from "node:test"
import { FogHexagonSource } from "../../app-phoenix/assets/js/map/layers/fog_hexagon_source.js"
import { FogLayer } from "../../app-phoenix/assets/js/map/layers/fog.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const library = {
  isValidCell: () => true,
  getResolution: () => 9,
  cellToParent: (id, res) => `${id}-${res}`,
  cellToLatLng: () => [52, 13],
  getHexagonEdgeLengthAvg: () => 1,
  UNITS: { km: "km" },
  cellToBoundary: () => [
    [13, 52],
    [13.01, 52],
    [13, 52.01],
  ],
}
function fixture() {
  const listeners = new Map(),
    timers = new Map()
  let roots = 0,
    size = 0
  const ctx = {
    clearRect() {},
    fillRect() {},
    beginPath() {},
    arc() {},
    fill() {},
    stroke() {},
    moveTo() {},
    lineTo() {},
    closePath() {},
  }
  const container = {
    offsetWidth: 390,
    offsetHeight: 200,
    appendChild() {
      roots++
    },
  }
  const map = {
    getContainer: () => container,
    getZoom: () => 4,
    querySourceFeatures: () => [],
    project: () => ({ x: 1, y: 1 }),
    getBounds: () => ({
      getWest: () => -180,
      getEast: () => 180,
      getSouth: () => -90,
      getNorth: () => 90,
    }),
    on(event, fn) {
      listeners.set(event, new Set([...(listeners.get(event) ?? []), fn]))
    },
    off(event, fn) {
      listeners.get(event)?.delete(fn)
    },
    emit(event) {
      for (const fn of listeners.get(event) ?? []) fn()
    },
  }
  const document = {
    createElement() {
      return {
        style: {},
        getContext: () => ctx,
        remove() {
          roots--
        },
        set width(value) {
          size++
        },
        set height(value) {
          size++
        },
      }
    },
  }
  const clock = {
    setTimeout(fn) {
      const id = Symbol()
      timers.set(id, fn)
      return id
    },
    clearTimeout(id) {
      timers.delete(id)
    },
  }
  return {
    map,
    document,
    clock,
    listeners,
    timers,
    roots: () => roots,
    size: () => size,
  }
}

test("style replacement restores density layers once", () => {
  const f = fixture()
  const fog = new FogLayer(f.map, {
    document: f.document,
    timers: f.clock,
    visible: true,
    tiledSource: true,
  })
  fog.add({ features: [] })
  fog.add({ features: [] })
  assert.equal(f.roots(), 1)
  assert.equal(f.listeners.get("resize").size, 1)
  fog.remove()
  assert.equal(f.roots(), 0)
})

test("destroy drains density fetch and resize callbacks", async () => {
  const f = fixture(),
    pending = deferred()
  let signal
  const source = new FogHexagonSource({ loadLibrary: async () => library })
  const fog = new FogLayer(f.map, {
    document: f.document,
    timers: f.clock,
    visible: true,
    mode: "hexagons",
    getRange: () => ({ startAt: "old", endAt: "old" }),
    hexSource: source,
    reader: {
      read(_kind, _params, options) {
        signal = options.signal
        return pending.promise
      },
    },
  })
  fog.add({ features: [] })
  for (let i = 0; i < 8; i++) await Promise.resolve()
  f.map.emit("zoomend")
  fog.remove()
  assert.equal(signal.aborted, true)
  const sizes = f.size()
  f.map.emit("resize")
  assert.equal(f.size(), sizes)
  assert.equal(
    [...f.listeners.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
  assert.equal(f.timers.size, 0)
  pending.resolve({ data: { h3_indexes: ["stale"] } })
  for (let i = 0; i < 12; i++) await Promise.resolve()
  assert.deepEqual(source.rawCellIds, [])
  assert.equal(f.roots(), 0)
})

test("older fog date response cannot replace current cells", async () => {
  const old = deferred(),
    current = deferred()
  const source = new FogHexagonSource({ loadLibrary: async () => library })
  const reader = {
    read(_kind, params) {
      return params.start_date === "old" ? old.promise : current.promise
    },
  }
  const first = source
    .load(reader, { start_at: "old" })
    .catch((error) => error.name)
  const second = source.load(reader, { start_at: "current" })
  current.resolve({ data: { h3_indexes: ["current"] } })
  await second
  old.resolve({ data: { h3_indexes: ["old"] } })
  assert.equal(await first, "AbortError")
  assert.deepEqual(source.rawCellIds, ["current"])
  assert.equal(source.boundariesFor(4).length, 1)
  source.destroy()
})

test("fog reads use the API date window rather than point timestamp parameters", async () => {
  const source = new FogHexagonSource({ loadLibrary: async () => library })
  let request
  await source.load(
    {
      async read(kind, params) {
        request = { kind, params }
        return { data: { h3_indexes: [] } }
      },
    },
    { start_at: "2026-03-29", end_at: "2026-03-30" },
  )
  assert.deepEqual(request, {
    kind: "fog",
    params: { start_date: "2026-03-29", end_date: "2026-03-30" },
  })
  source.destroy()
})
