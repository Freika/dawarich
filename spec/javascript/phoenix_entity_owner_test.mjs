import assert from "node:assert/strict"
import { test } from "node:test"
import { createEntityLayers } from "../../app-phoenix/assets/js/map/layers/entities.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const row = (id) => ({
  id,
  name: `Visit ${id}`,
  place: { name: "Place", latitude: 52, longitude: 13 },
  status: "confirmed",
  started_at: "2026-03-29T00:00:00Z",
  ended_at: "2026-03-29T01:00:00Z",
  duration: 3600,
})
const config = {
  range: { startAt: "2026-03-29", endAt: "2026-03-30" },
  visitsEnabled: true,
  placesEnabled: false,
  areasEnabled: false,
  anomaliesEnabled: false,
}
function fixture() {
  const sources = new Map(),
    layers = new Map(),
    events = new Map(),
    filters = new Map(),
    popups = []
  const map = {
    getBounds: () => ({
      getSouth: () => 50,
      getNorth: () => 55,
      getWest: () => 10,
      getEast: () => 15,
    }),
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
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
    setFilter(id, filter) {
      filters.set(id, filter)
    },
    getCanvas: () => ({ style: {} }),
    on(event, layer, fn) {
      const key = typeof layer === "string" ? `${event}:${layer}` : event
      events.set(key, new Set([...(events.get(key) ?? []), fn ?? layer]))
    },
    off(event, layer, fn) {
      const key = typeof layer === "string" ? `${event}:${layer}` : event
      events.get(key)?.delete(fn ?? layer)
    },
    emit(event, value) {
      for (const fn of events.get(event) ?? []) fn(value)
    },
  }
  class Popup {
    constructor() {
      popups.push(this)
    }
    setLngLat() {
      return this
    }
    setHTML(html) {
      this.html = html
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  return { map, sources, layers, events, filters, library: { Popup }, popups }
}

test("viewport visits replace once without stale results", async () => {
  const f = fixture(),
    old = deferred(),
    latest = deferred()
  let n = 0,
    signal
  const owner = createEntityLayers({
    ...f,
    reader: {
      pages(kind, params, options) {
        assert.equal(kind, "visits")
        assert.deepEqual(params, {
          start_at: config.range.startAt,
          end_at: config.range.endAt,
          selection: "true",
          sw_lat: 50,
          sw_lng: 10,
          ne_lat: 55,
          ne_lng: 15,
        })
        signal = options.signal
        return ++n === 1 ? old.promise : latest.promise
      },
    },
  })
  const first = owner.update(config)
  const previous = signal
  const second = owner.update({ ...config, revision: 2 })
  assert.equal(previous.aborted, true)
  latest.resolve([row(2)])
  await second
  old.resolve([row(1)])
  await assert.rejects(first, { name: "AbortError" })
  assert.deepEqual(
    f.sources.get("visits-source").data.features.map((f) => f.properties.id),
    [2],
  )
  assert.equal(f.layers.size, 4)
  owner.destroy()
  assert.equal(f.sources.size, 0)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})

test("popup selection reports only its explicit resource identity", async () => {
  const f = fixture(),
    selections = []
  const owner = createEntityLayers({
    ...f,
    onSelect: (receipt) => selections.push(receipt),
    reader: { pages: async () => [row(2)] },
  })
  await owner.update(config)
  f.map.emit("click:visits", {
    features: [
      {
        properties: {
          id: 2,
          name: "synthetic-private-metadata",
          api_key: "synthetic-forbidden",
        },
      },
    ],
    lngLat: [13, 52],
  })
  f.map.emit("click:visits", { features: [{ properties: { id: 999 } }] })
  assert.deepEqual(selections, [{ kind: "visit", id: 2 }])
  owner.destroy()
  f.map.emit("click:visits", { features: [{ properties: { id: 2 } }] })
  assert.equal(selections.length, 1)
})

test("entity style replacement retains day selection and one listener set", async () => {
  const f = fixture()
  const owner = createEntityLayers({
    ...f,
    reader: { pages: async () => [row(2)] },
  })
  await owner.update(config)
  owner.visitPresentation({
    selectedId: 2,
    dayRoute: [
      { lng: 13, lat: 52 },
      { lng: 14, lat: 53 },
    ],
    status: { confirmed: false, suggested: true, declined: false },
  })
  f.sources.clear()
  f.layers.clear()
  f.map.emit("style.load")
  f.map.emit("style.load")
  assert.equal(f.sources.size, 2)
  assert.equal(f.layers.size, 4)
  assert.equal(f.events.get("click:visits").size, 1)
  assert.deepEqual(f.filters.get("visits-halo"), ["==", ["get", "id"], 2])
  assert.deepEqual(
    f.sources.get("visits-source-day-route").data.features[0].geometry
      .coordinates,
    [
      [13, 52],
      [14, 53],
    ],
  )
  owner.destroy()
})

test("empty place tags suppress reads while selected anomalies remain visible", async () => {
  const f = fixture(),
    requests = []
  const owner = createEntityLayers({
    ...f,
    reader: {
      pages: async (kind, params) => {
        requests.push({ kind, params })
        return []
      },
    },
  })
  await owner.update({
    ...config,
    visitsEnabled: false,
    placesEnabled: true,
    placesTagFilters: [],
  })
  assert.equal(requests.length, 0)
  await owner.update({
    ...config,
    visitsEnabled: false,
    placesEnabled: true,
    placesTagFilters: [11, "untagged"],
  })
  assert.deepEqual(requests, [
    { kind: "places", params: { tag_ids: [11, "untagged"] } },
  ])
  owner.selected({
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [13, 52] },
        properties: { id: 8, anomaly: true },
      },
    ],
  })
  assert.equal(f.sources.get("selected-points-source").data.features.length, 1)
  owner.destroy()
  assert.equal(f.sources.size, 0)
})

test("viewport movement waits for the active range and refreshes only visits", async () => {
  const f = fixture(),
    pending = deferred(),
    requests = []
  const owner = createEntityLayers({
    ...f,
    reader: {
      pages: async (kind) => {
        requests.push(kind)
        return kind === "visits" ? pending.promise : []
      },
    },
  })
  const load = owner.update({ ...config, placesEnabled: true })
  load.catch(() => {})
  try {
    f.map.emit("moveend")
    assert.deepEqual(requests, ["visits", "places"])
    pending.resolve([row(2)])
    await load
    for (let i = 0; i < 32; i++) await Promise.resolve()
    assert.deepEqual(requests, ["visits", "places", "visits"])
    assert.equal(
      f.sources.get("visits-source").data.features[0].properties.id,
      2,
    )
  } finally {
    pending.resolve([])
    owner.destroy()
    await Promise.allSettled([load])
  }
})

test("native entity host loads on demand and exposes only owned selection receipts", async () => {
  const { mountHost } = await import(
    "../../app-phoenix/assets/js/map/runtime/host.js"
  )
  const f = fixture(),
    receipts = []
  let reads = 0,
    removed = 0,
    closed = 0
  Object.assign(f.map, {
    loaded: () => true,
    remove: () => removed++,
    getStyle: () => ({ layers: [] }),
    setPaintProperty() {},
  })
  const reader = {
    reset() {},
    destroy() {
      closed++
    },
    async pages(kind) {
      assert.equal(kind, "visits")
      reads++
      return [row(2)]
    },
  }
  const initial = { ...config, visitsEnabled: false }
  const element = {
    dataset: { mapConfig: JSON.stringify(initial) },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  class FakeMap {
    constructor() {
      Object.assign(this, f.map)
    }
  }
  const owner = mountHost({
    element,
    reader,
    pushEvent: (name, payload) => receipts.push({ name, payload }),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    loadLibrary: async () => ({ ...f.library, Map: FakeMap }),
  })
  assert.equal(await owner.mount(), "ready")
  assert.equal(reads, 0)
  assert.equal(await owner.update(config), "ready")
  assert.equal(reads, 1)
  f.map.emit("click:visits", {
    features: [{ properties: { id: 2, name: "synthetic-hidden" } }],
  })
  assert.deepEqual(
    receipts.filter((r) => r.name === "map:select"),
    [{ name: "map:select", payload: { kind: "visit", id: 2 } }],
  )
  const service = owner.entityLayers
  assert.equal(await owner.reconnect(), "ready")
  assert.equal(owner.entityLayers, service)
  owner.destroy()
  assert.equal(f.sources.size, 0)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
  assert.equal(closed, 1)
  assert.equal(removed, 1)
})

test("entity range replacement refreshes the anomaly info card locale", async () => {
  const f = fixture()
  const cards = []
  const owner = createEntityLayers({
    ...f,
    onInfo: (receipt) => cards.push(receipt),
    reader: {
      pages: async () => [
        {
          id: 1,
          latitude: 52,
          longitude: 13,
          timestamp: 1790000000,
          accuracy: 101,
        },
      ],
    },
  })
  const state = {
    ...config,
    visitsEnabled: false,
    anomaliesEnabled: true,
    entityLabels: {
      "map_info.time": "Time",
      "map_info.reason": "Reason",
      "anomalies.low_accuracy": "Low {accuracy}/{threshold}",
    },
  }
  await owner.update(state)
  f.map.emit("click:anomalies", { features: [{ properties: { id: 1 } }] })
  assert.equal(cards[0].kind, "point")
  assert.ok(cards[0].content.includes("Time"))
  await owner.update({
    ...state,
    range: { ...config.range, timezone: "Europe/Berlin" },
    entityLabels: {
      "map_info.time": "Zeit",
      "map_info.reason": "Grund",
      "anomalies.low_accuracy": "Genauigkeit {accuracy}/{threshold}",
    },
  })
  f.map.emit("click:anomalies", { features: [{ properties: { id: 1 } }] })
  assert.ok(cards[1].content.includes("Zeit"))
  assert.ok(cards[1].content.includes("Genauigkeit 101/100"))
  assert.ok(!cards[1].content.includes("Time"))
  assert.equal(f.popups.length, 0)
  owner.destroy()
})
