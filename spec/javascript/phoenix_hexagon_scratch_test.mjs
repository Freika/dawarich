import assert from "node:assert/strict"
import { test } from "node:test"
import { HexagonSource } from "../../app-phoenix/assets/js/map/layers/hexagon_source.js"
import { HexagonLayer } from "../../app-phoenix/assets/js/map/layers/hexagon.js"
import { ScratchLayer } from "../../app-phoenix/assets/js/map/layers/scratch.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const h3 = {
  latLngToCell: (_lat, _lng, res) => String(res),
  cellToBoundary: () => [
    [52, 13],
    [53, 13],
    [52, 14],
  ],
}
function mapFixture() {
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map()
  let paints = 0
  const map = {
    sources,
    layers,
    listeners,
    getZoom: () => 4,
    getCanvas: () => ({ style: {} }),
    setFeatureState() {},
    getSource(id) {
      return sources.get(id)
    },
    getLayer(id) {
      return layers.get(id)
    },
    getStyle() {
      return { layers: [...layers.values()] }
    },
    addSource(id, source) {
      sources.set(id, {
        ...source,
        setData(data) {
          paints++
          this.data = data
        },
      })
    },
    removeSource(id) {
      sources.delete(id)
    },
    addLayer(layer) {
      layers.set(layer.id, layer)
    },
    removeLayer(id) {
      layers.delete(id)
    },
    setLayoutProperty() {},
    setFilter(id, filter) {
      layers.get(id).filter = filter
    },
    on(event, layer, fn) {
      const callback = fn ?? layer
      listeners.set(event, new Set([...(listeners.get(event) ?? []), callback]))
    },
    off(event, layer, fn) {
      listeners.get(event)?.delete(fn ?? layer)
    },
    emit(event) {
      for (const callback of listeners.get(event) ?? []) callback()
    },
  }
  class Popup {
    remove() {}
    setText() {
      return this
    }
    setLngLat() {
      return this
    }
    addTo() {
      return this
    }
  }
  return { map, library: { Popup }, paints: () => paints }
}

test("hexagon page completing after remove cannot repaint its layer", async () => {
  const f = mapFixture(),
    pending = deferred()
  let signal
  const layer = new HexagonLayer(f.map, {
    library: f.library,
    loadH3: async () => h3,
    reader: {
      pages(_kind, _params, options) {
        signal = options.signal
        return pending.promise
      },
    },
  })
  layer.add({ type: "FeatureCollection", features: [] })
  const reading = layer
    .load({ start_at: "one", end_at: "two" })
    .catch((e) => e.name)
  for (let i = 0; i < 8; i++) await Promise.resolve()
  layer.remove()
  assert.equal(signal.aborted, true)
  const before = f.paints()
  pending.resolve([{ latitude: 52, longitude: 13, timestamp: 1 }])
  assert.equal(await reading, "AbortError")
  assert.equal(f.paints(), before)
  assert.equal(f.map.sources.size, 0)
  assert.equal(
    [...f.map.listeners.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})

test("hexagon zoom reaggregates retained points with the original resolution thresholds", async () => {
  let paints = 0
  const source = new HexagonSource({
    loadLibrary: async () => h3,
    reader: {
      async pages() {
        return [
          { latitude: 52, longitude: 13, timestamp: 10 },
          { latitude: 52, longitude: 13, timestamp: 20 },
          { latitude: "invalid", longitude: 0 },
        ]
      },
    },
    onData() {
      paints++
    },
  })
  await source.load({ start_at: "one", end_at: "two" }, 4)
  assert.equal(source.data.features[0].properties.h3_index, "4")
  assert.equal(source.data.features[0].properties.count, 2)
  source.zoom(12)
  assert.equal(source.data.features[0].properties.h3_index, "8")
  assert.equal(source.data.features[0].geometry.coordinates[0].length, 4)
  assert.equal(source.data.features[0].properties.log_count, Math.log10(2))
  assert.ok(paints >= 2)
  source.destroy()
})

test("scratch protocol or membership reads cannot outlive their owner", async () => {
  const f = mapFixture(),
    protocol = deferred(),
    membership = deferred()
  const early = new ScratchLayer(f.map, {
    loadProtocol: () => protocol.promise,
    reader: { read: () => membership.promise },
    getRange: () => ({ startAt: "one", endAt: "two" }),
  })
  const mounting = early.add().catch((e) => e.name)
  early.destroy()
  protocol.resolve()
  assert.equal(await mounting, "AbortError")
  assert.equal(f.map.sources.size, 0)
  let signal
  const late = new ScratchLayer(f.map, {
    loadProtocol: async () => {},
    reader: {
      read(_kind, _params, options) {
        signal = options.signal
        return membership.promise
      },
    },
    getRange: () => ({ startAt: "one", endAt: "two", importId: 3 }),
  })
  const mounted = late.add().catch((e) => e.name)
  for (let i = 0; i < 10; i++) await Promise.resolve()
  late.destroy()
  assert.equal(signal.aborted, true)
  membership.resolve({ data: { countries: [{ iso_a3: "DEU" }] } })
  await mounted
  assert.deepEqual(late.visitedIsoA3, [])
  assert.equal(f.map.sources.size, 0)
})

test("hexagon deadline clears partial counts and reports a visible failure", async () => {
  const f = mapFixture(),
    pending = deferred()
  let expire
  const errors = []
  const layer = new HexagonLayer(f.map, {
    library: f.library,
    loadH3: async () => h3,
    timers: {
      setTimeout(fn) {
        expire = fn
        return 1
      },
      clearTimeout() {},
    },
    onError: (code) => errors.push(code),
    reader: {
      pages(_kind, _params, options) {
        options.onPage({
          data: [{ latitude: 52, longitude: 13, timestamp: 1 }],
        })
        return pending.promise
      },
    },
  })
  layer.add({ type: "FeatureCollection", features: [] })
  const request = layer
    .load({ start_at: "one", end_at: "two" })
    .catch((e) => e.name)
  try {
    for (let i = 0; i < 12; i++) await Promise.resolve()
    assert.equal(layer.source.data.features.length, 1)
    expire()
    assert.equal(await request, "AbortError")
    assert.equal(layer.source.data.features.length, 0)
    assert.deepEqual(errors, ["hexagons_load_failed"])
  } finally {
    layer.remove()
    pending.resolve([])
  }
})

test("scratch deadline refuses unknown membership instead of treating it as empty", async () => {
  const f = mapFixture(),
    pending = deferred()
  let expire
  const layer = new ScratchLayer(f.map, {
    loadProtocol: async () => {},
    getRange: () => ({ startAt: "one", endAt: "two" }),
    reader: { read: () => pending.promise },
    timers: {
      setTimeout(fn) {
        expire = fn
        return 1
      },
      clearTimeout() {},
    },
  })
  let rejected = false
  const read = layer.update().catch(() => {
    rejected = true
  })
  try {
    assert.equal(typeof expire, "function")
    expire()
    for (let i = 0; i < 16; i++) await Promise.resolve()
    assert.equal(rejected, true)
    assert.equal(layer.stale, true)
  } finally {
    layer.destroy()
    pending.resolve({ data: { countries: [] } })
    await read
  }
})
