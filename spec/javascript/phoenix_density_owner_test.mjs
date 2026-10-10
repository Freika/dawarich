import assert from "node:assert/strict"
import { test } from "node:test"
import { createDensityLayers } from "../../app-phoenix/assets/js/map/layers/density.js"

function fixture() {
  const sources = new Map(),
    layers = new Map(),
    events = new Map()
  let canvases = 0,
    points = 0
  const document = {
    createElement() {
      return {
        style: {},
        getContext: () => ({
          clearRect() {},
          fillRect() {},
          beginPath() {},
          arc() {},
          fill() {},
          stroke() {},
          closePath() {},
          moveTo() {},
          lineTo() {},
        }),
        remove() {
          canvases--
        },
      }
    },
  }
  const container = {
    ownerDocument: document,
    offsetWidth: 390,
    offsetHeight: 240,
    appendChild() {
      canvases++
    },
  }
  const map = {
    getContainer: () => container,
    getZoom: () => 4,
    getCanvas: () => ({ style: {} }),
    querySourceFeatures: () => [],
    project: () => ({ x: 1, y: 1 }),
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    getStyle: () => ({ layers: [...layers.values()] }),
    addSource(id, source) {
      sources.set(id, {
        ...source,
        setData(data) {
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
    setFilter() {},
    setFeatureState() {},
    on(event, layer, handler) {
      events.set(
        event,
        new Set([...(events.get(event) ?? []), handler ?? layer]),
      )
    },
    off(event, layer, handler) {
      events.get(event)?.delete(handler ?? layer)
    },
    emit(event) {
      for (const handler of events.get(event) ?? []) handler()
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
  const reader = {
    async pages(_kind, _params, options) {
      points++
      const data = [{ latitude: 52, longitude: 13, timestamp: 1 }]
      options.onPage?.({ data })
      return data
    },
    async read(kind) {
      return {
        data: kind === "countries" ? { countries: [] } : { h3_indexes: [] },
      }
    },
  }
  const h3 = {
    latLngToCell: () => "cell",
    cellToBoundary: () => [
      [52, 13],
      [52, 14],
      [53, 13],
    ],
    isValidCell: () => true,
  }
  return {
    map,
    reader,
    library: { Popup },
    h3,
    events,
    sources,
    layers,
    canvases: () => canvases,
    points: () => points,
  }
}
const config = {
  revision: 1,
  epoch: 1,
  range: { startAt: "2026-03-29", endAt: "2026-03-30" },
  fogEnabled: true,
  fogMode: "points",
  hexagonsEnabled: true,
  scratchEnabled: true,
}

test("density owner restores style resources once and releases only its map", async () => {
  const f = fixture(),
    other = fixture()
  const owner = createDensityLayers({
    map: f.map,
    reader: f.reader,
    library: f.library,
    loadH3: async () => f.h3,
    loadProtocol: async () => {},
  })
  const second = createDensityLayers({
    map: other.map,
    reader: other.reader,
    library: other.library,
    loadH3: async () => other.h3,
    loadProtocol: async () => {},
  })
  await owner.update(config)
  await second.update(config)
  assert.equal(f.canvases(), 1)
  assert.equal(f.points(), 1)
  f.sources.clear()
  f.layers.clear()
  f.map.emit("style.load")
  f.map.emit("style.load")
  for (let i = 0; i < 16; i++) await Promise.resolve()
  assert.equal(f.sources.size, 2)
  assert.equal(f.layers.size, 4)
  owner.destroy()
  assert.equal(f.canvases(), 0)
  assert.equal(f.sources.size, 0)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
  assert.equal(other.canvases(), 1)
  assert.equal(other.sources.size, 2)
  second.destroy()
})

test("disabled density owners never read exact points and cannot restart after destruction", async () => {
  const f = fixture()
  const owner = createDensityLayers({
    map: f.map,
    reader: f.reader,
    library: f.library,
  })
  await owner.update({
    ...config,
    fogEnabled: false,
    hexagonsEnabled: false,
    scratchEnabled: false,
  })
  assert.equal(f.points(), 0)
  owner.destroy()
  f.map.emit("style.load")
  await assert.rejects(owner.update(config), { name: "AbortError" })
  assert.equal(f.sources.size, 0)
  assert.equal(f.canvases(), 0)
})

test("native host lazily owns density and reconnect never duplicates its canvas", async () => {
  const { mountHost } = await import(
    "../../app-phoenix/assets/js/map/runtime/host.js"
  )
  const f = fixture()
  let removed = 0,
    readerClosed = 0
  Object.assign(f.map, {
    loaded: () => true,
    remove: () => removed++,
    setPaintProperty() {},
  })
  Object.assign(f.reader, {
    reset() {},
    destroy() {
      readerClosed++
    },
  })
  const element = {
    dataset: {
      mapConfig: JSON.stringify({
        ...config,
        fogEnabled: false,
        hexagonsEnabled: false,
        scratchEnabled: false,
      }),
    },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  class FakeMap {
    constructor() {
      Object.assign(this, f.map)
    }
  }
  const receipts = []
  const owner = mountHost({
    element,
    reader: f.reader,
    pushEvent: (name) => receipts.push(name),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    loadLibrary: async () => ({ Map: FakeMap, Popup: f.library.Popup }),
  })
  assert.equal(await owner.mount(), "ready")
  assert.equal(f.canvases(), 0)
  assert.equal(
    await owner.update({
      ...config,
      hexagonsEnabled: false,
      scratchEnabled: false,
    }),
    "ready",
  )
  assert.equal(f.canvases(), 1)
  for (let i = 0; i < 10; i++) assert.equal(await owner.reconnect(), "ready")
  assert.equal(f.canvases(), 1)
  assert.equal(f.points(), 0)
  owner.destroy()
  assert.equal(f.canvases(), 0)
  assert.equal(removed, 1)
  assert.equal(readerClosed, 1)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
  assert.equal(receipts.length, 12)
})
