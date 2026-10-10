import assert from "node:assert/strict"
import { test } from "node:test"
import { mountFamily } from "../../app-phoenix/assets/js/map/family/runtime.js"

const defer = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
function fixture() {
  const sources = new Map(),
    layers = new Map(),
    events = new Map(),
    intervals = new Set(),
    popups = []
  let maps = 0,
    removed = 0,
    reads = []
  const canvas = { style: {}, addEventListener() {}, removeEventListener() {} }
  class MapView {
    constructor() {
      maps++
    }
    loaded() {
      return true
    }
    remove() {
      removed++
    }
    getCanvas() {
      return canvas
    }
    on(e, a, b) {
      const k = b ? `${e}:${a}` : e
      events.set(k, new Set([...(events.get(k) ?? []), b ?? a]))
    }
    off(e, a, b) {
      events.get(b ? `${e}:${a}` : e)?.delete(b ?? a)
    }
    once(e, f) {
      this.on(e, f)
    }
    getSource(id) {
      return sources.get(id)
    }
    getLayer(id) {
      return layers.get(id)
    }
    addSource(id, s) {
      sources.set(id, {
        ...s,
        setData(data) {
          this.data = data
        },
      })
    }
    removeSource(id) {
      sources.delete(id)
    }
    addLayer(l) {
      layers.set(l.id, l)
    }
    removeLayer(id) {
      layers.delete(id)
    }
    fitBounds() {}
  }
  class Popup {
    constructor() {
      popups.push(this)
    }
    setLngLat() {
      return this
    }
    setHTML(h) {
      this.html = h
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  const timers = {
    setTimeout,
    clearTimeout,
    setInterval(fn) {
      intervals.add(fn)
      return fn
    },
    clearInterval(fn) {
      intervals.delete(fn)
    },
  }
  const element = {
    dataset: {
      mapConfig: JSON.stringify({
        revision: 1,
        locale: "de",
        range: { startAt: "2026-10-01", endAt: "2026-10-04" },
        mapOptions: {},
      }),
    },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const reader = {
    read(resource, params, opts) {
      reads.push({ resource, params, opts })
      return Promise.resolve({
        data:
          resource === "family_locations"
            ? {
                locations: [
                  {
                    user_id: 7,
                    name: "<Member>",
                    latitude: 52,
                    longitude: 13,
                    timestamp: 1_790_000_000,
                  },
                ],
              }
            : {
                members: [
                  {
                    user_id: 7,
                    points: [
                      [52, 13, 1],
                      [53, 14, 2],
                    ],
                  },
                ],
              },
      })
    },
    reset() {},
    destroy() {
      this.destroyed = true
    },
  }
  const owner = mountFamily({
    element,
    reader,
    timers,
    loadLibrary: async () => ({ Map: MapView, Popup }),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    pushEvent() {},
  })
  return {
    owner,
    reader,
    sources,
    layers,
    events,
    intervals,
    popups,
    get maps() {
      return maps
    },
    get removed() {
      return removed
    },
    get reads() {
      return reads
    },
  }
}
test("withdrawn family consent clears markers and rejects late updates", async () => {
  const f = fixture()
  await f.owner.mount()
  assert.equal(f.sources.get("family-members").data.features.length, 1)
  const old = defer()
  f.reader.read = () => old.promise
  const pending = f.owner.reconnect()
  await Promise.resolve()
  assert.equal(f.sources.get("family-members").data.features.length, 0)
  f.reader.read = async (resource) => ({
    data: resource === "family_locations" ? { locations: [] } : { members: [] },
  })
  await f.owner.reconnect()
  old.resolve({
    data: {
      locations: [{ user_id: 7, latitude: 52, longitude: 13 }],
      members: [
        {
          user_id: 7,
          points: [
            [52, 13, 1],
            [53, 14, 2],
          ],
        },
      ],
    },
  })
  await pending
  assert.equal(f.sources.get("family-members").data.features.length, 0)
  assert.equal(f.sources.get("family-history").data.features.length, 0)
  f.owner.destroy()
  assert.equal(f.intervals.size, 0)
  assert.equal(f.reader.destroyed, true)
})
test("family reconnect refreshes membership without a second map", async () => {
  const f = fixture()
  await f.owner.mount()
  await f.owner.reconnect()
  assert.equal(f.maps, 1)
  assert.equal(f.reads.length, 4)
  assert.deepEqual(
    new Set(f.reads.map((r) => r.resource)),
    new Set(["family_locations", "family_history"]),
  )
  assert.equal(
    f.sources.get("family-history").data.features[0].geometry.coordinates
      .length,
    2,
  )
  f.sources.clear()
  f.layers.clear()
  for (const fn of f.events.get("style.load")) fn()
  assert.equal(f.sources.get("family-members").data.features.length, 1)
  f.owner.destroy()
  assert.equal(f.removed, 1)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})
test("family relative time is localized and popup cannot outlive consent", async () => {
  const f = fixture()
  await f.owner.mount()
  for (const fn of f.events.get("click:family-circles"))
    fn({ features: [{ properties: { id: 7 } }], lngLat: [13, 52] })
  assert.match(f.popups[0].html, /&lt;Member&gt;/)
  assert.match(f.popups[0].html, /vor/)
  assert.equal(f.intervals.size, 1)
  f.owner.clear()
  assert.equal(f.popups[0].removed, true)
  assert.equal(f.sources.get("family-history").data.features.length, 0)
  f.owner.destroy()
})

test("family clear cancels an outstanding read even when transport ignores abort", async () => {
  const f = fixture()
  await f.owner.mount()
  const late = defer()
  f.reader.read = () => late.promise
  const pending = f.owner.reconnect()
  await Promise.resolve()
  f.owner.clear()
  late.resolve({
    data: {
      locations: [{ user_id: 7, latitude: 52, longitude: 13 }],
      members: [],
    },
  })
  await pending
  assert.equal(f.sources.get("family-members").data.features.length, 0)
  f.owner.destroy()
})
