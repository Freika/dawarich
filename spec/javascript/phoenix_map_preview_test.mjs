import assert from "node:assert/strict"
import { test } from "node:test"
import {
  createPreviewGate,
  mountPreview,
} from "../../app-phoenix/assets/js/map/preview/runtime.js"
import { createPublicStatsReader } from "../../app-phoenix/assets/js/map/public/stats_reader.js"

const turn = () => new Promise((r) => setImmediate(r))
function fixture(gate = createPreviewGate(2)) {
  let visible,
    constructed = 0,
    removed = 0,
    refreshed = 0
  const element = {
    dataset: { mapConfig: JSON.stringify({ tripId: 4 }) },
    ownerDocument: {},
  }
  const owner = mountPreview({
    element,
    gate,
    observe: (_, callback) => {
      visible = callback
      return () => {
        visible = null
      }
    },
    createOwner: () => {
      constructed++
      return {
        mount: async () => "ready",
        destroy: () => {
          removed++
        },
        update: async () => {
          refreshed++
        },
      }
    },
  })
  return {
    owner,
    show: (v) => visible?.(v),
    get constructed() {
      return constructed
    },
    get removed() {
      return removed
    },
    get refreshed() {
      return refreshed
    },
  }
}
test("hidden preview does not allocate a map and leaving destroys all initialized previews", async () => {
  const f = fixture()
  f.owner.mount()
  await turn()
  assert.equal(f.constructed, 0)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 1)
  f.show(false)
  await turn()
  assert.equal(f.removed, 1)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 2)
  f.owner.destroy()
  assert.equal(f.removed, 2)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 2)
})
test("preview queue caps live owners and drops destroyed queued previews", async () => {
  const gate = createPreviewGate(1),
    a = fixture(gate),
    b = fixture(gate),
    c = fixture(gate)
  for (const f of [a, b, c]) {
    f.owner.mount()
    f.show(true)
  }
  await turn()
  assert.equal(a.constructed, 1)
  assert.equal(b.constructed, 0)
  assert.equal(c.constructed, 0)
  b.owner.destroy()
  a.owner.destroy()
  await turn()
  assert.equal(b.constructed, 0)
  assert.equal(c.constructed, 1)
  c.owner.destroy()
  assert.equal(gate.active, 0)
})
test("preview configuration patches reuse a visible owner and preserve readonly settings", async () => {
  const f = fixture()
  f.owner.mount()
  f.show(true)
  await turn()
  await f.owner.update({ tripId: 5, revision: 2 })
  assert.equal(f.constructed, 1)
  assert.equal(f.refreshed, 1)
  f.owner.destroy()
})
test("public stats preview never requests private geometry or account credentials", async () => {
  const calls = []
  const reader = createPublicStatsReader({
    origin: "https://maps.example",
    fetch: async (url, options) => {
      calls.push({ url, options })
      return { ok: true, json: async () => ({ features: [] }) }
    },
  })
  const result = await reader.read("hexagons", {
    uuid: "public-share",
    start_date: "1900-01-01",
    api_key: "synthetic-secret",
  })
  assert.deepEqual(result.data, { features: [] })
  const url = new URL(calls[0].url)
  assert.equal(url.pathname, "/api/v1/maps/hexagons")
  assert.deepEqual([...url.searchParams], [["uuid", "public-share"]])
  assert.equal(calls[0].options.credentials, "omit")
  assert.equal(calls[0].options.headers.Authorization, undefined)
  await assert.rejects(
    reader.read("points", { uuid: "public-share" }),
    /Unsupported/,
  )
  reader.destroy()
})
test("public stats destruction aborts a noncooperative geometry response", async () => {
  let complete, signal
  const reader = createPublicStatsReader({
    origin: "https://maps.example",
    fetch: async (_, options) => {
      signal = options.signal
      return new Promise((r) => {
        complete = r
      })
    },
  })
  const reading = reader.read("hexagons", { uuid: "share" })
  await turn()
  reader.destroy()
  complete({ ok: true, json: async () => ({ features: [{ id: 1 }] }) })
  await assert.rejects(reading, (e) => e.name === "AbortError")
  assert.equal(signal.aborted, true)
})

test("preview route uses owned HTTP geometry across dateline and clears stale empty path", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map(),
    reads = []
  let removed = 0,
    mapOptions,
    path = [
      [179, 10],
      [-179, 11],
    ]
  const element = {
    dataset: {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  class MapLibre {
    constructor(options) {
      mapOptions = options
    }
    loaded() {
      return true
    }
    on(name, f) {
      listeners.set(name, f)
    }
    once(name, f) {
      listeners.set(name, f)
    }
    off(name) {
      listeners.delete(name)
    }
    addSource(id, s) {
      sources.set(id, s)
    }
    addLayer(l) {
      layers.set(l.id, l)
    }
    getSource(id) {
      return sources.get(id)
    }
    getLayer(id) {
      return layers.get(id)
    }
    removeSource(id) {
      sources.delete(id)
    }
    removeLayer(id) {
      layers.delete(id)
    }
    fitBounds() {}
    remove() {
      removed++
    }
  }
  const library = {
    Map: MapLibre,
    LngLatBounds: class {
      extend() {}
      isEmpty() {
        return false
      }
    },
  }
  const reader = {
    read: async (resource, params) => {
      reads.push({ resource, params })
      return { data: { path, plan: null } }
    },
    reset() {},
    destroy() {},
  }
  const owner = createPreviewOwner({
    element,
    config: { tripId: 7, interactive: false },
    reader,
    loadLibrary: async () => library,
    loadStyle: async () => ({}),
  })
  assert.equal(await owner.mount(), "ready")
  assert.deepEqual(reads, [{ resource: "trip", params: { id: 7 } }])
  assert.equal(mapOptions.interactive, false)
  assert.equal(
    sources.get("preview-route").data.geometry.type,
    "MultiLineString",
  )
  assert.equal(sources.get("preview-route").data.geometry.coordinates.length, 2)
  path = []
  await owner.update({ tripId: 7, revision: 2 })
  assert.equal(sources.has("preview-route"), false)
  owner.destroy()
  assert.equal(layers.size, 0)
  assert.equal(sources.size, 0)
  assert.equal(listeners.size, 0)
  assert.equal(removed, 1)
})
