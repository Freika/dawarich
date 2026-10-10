import assert from "node:assert/strict"
import { test } from "node:test"
import { createPublicReader } from "../../app-phoenix/assets/js/map/public/reader.js"
import { mountPublic } from "../../app-phoenix/assets/js/map/public/runtime.js"

const id = "a1330000-0000-4000-8000-000000000001"
const config = {
  photoLabels: { "map_info.photo": "Foto" },
  shareId: id,
  revision: 1,
  publicType: "trip",
  photosEnabled: false,
  routeEnabled: true,
  range: { startAt: "2026-10-08", endAt: "2026-10-09", timezone: "UTC" },
}
const points = [
  [13, 52, 1791400000],
  [14, 53, 1791401000],
]
function fixture(overrides = {}) {
  let maps = 0,
    destroyed = 0,
    renders = 0,
    cleared = 0,
    photoLoads = 0
  const calls = [],
    events = []
  const element = {
    dataset: { mapConfig: JSON.stringify(config) },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const reader = {
    async read(resource) {
      calls.push(resource)
      return { data: resource === "metadata" ? { ...config } : points }
    },
    reset() {},
    destroy() {
      destroyed++
    },
  }
  const library = {
    Map: class {
      constructor() {
        maps++
      }
      loaded() {
        return true
      }
      remove() {}
      off() {}
    },
  }
  const owner = mountPublic({
    element,
    reader,
    pushEvent: (name, payload) => events.push([name, payload]),
    loadLibrary: async () => library,
    loadStyle: async () => ({}),
    createLayers: () => ({
      show() {
        renders++
      },
      clear() {
        cleared++
      },
      destroy() {},
      selectDay() {},
    }),
    ...overrides,
    loadPhotos:
      overrides.loadPhotos ??
      (async () => ({
        add() {},
        remove() {},
        async load() {
          photoLoads++
          return "ready"
        },
      })),
  })
  return {
    owner,
    reader,
    calls,
    events,
    get maps() {
      return maps
    },
    get renders() {
      return renders
    },
    get cleared() {
      return cleared
    },
    get destroyed() {
      return destroyed
    },
    get photoLoads() {
      return photoLoads
    },
  }
}
test("public reader only uses its fixed capability paths and same-origin cookies", async () => {
  const calls = []
  const reader = createPublicReader({
    shareId: id,
    origin: "https://native.test",
    fetch: async (url, options) => {
      calls.push([url, options])
      return {
        ok: true,
        json: async () => [],
        blob: async () => new Blob(["image"]),
      }
    },
  })
  await reader.read("points", { api_key: "forbidden", id: "other" })
  await reader.read("thumbnail", {
    id: "photo/1",
    source: "immich",
    api_key: "forbidden",
  })
  assert.equal(
    calls[0][0],
    `https://native.test/native/public/maps/${id}/points`,
  )
  assert.match(calls[1][0], /photos\/photo%2F1\/thumbnail\?source=immich$/)
  assert.equal(calls[0][1].credentials, "same-origin")
  await assert.rejects(reader.read("settings"))
  reader.destroy()
})
test("expired revoked or re-locked public map drops in-flight data and clears route", async () => {
  const f = fixture()
  await f.owner.mount()
  assert.equal(f.renders, 1)
  let settle
  const waiting = new Promise((resolve) => {
    settle = resolve
  })
  f.reader.read = async (resource) =>
    resource === "metadata" ? { data: config } : waiting
  const pending = f.owner.reconnect()
  await Promise.resolve()
  f.owner.destroy()
  settle({ data: points })
  assert.equal(await pending, "cancelled")
  assert.equal(f.renders, 1)
  assert.equal(f.destroyed, 1)
  const g = fixture()
  await g.owner.mount()
  g.reader.read = async () => {
    throw new Error("locked")
  }
  const clears = g.cleared
  assert.equal(await g.owner.reconnect(), "failed")
  assert.equal(g.cleared, clears + 1)
  assert.equal(g.events.at(-1)[0], "map:failed")
})
test("show_photos false never loads photo bytes", async () => {
  const f = fixture()
  await f.owner.mount()
  assert.equal(f.photoLoads, 0)
  assert.ok(!f.calls.includes("photos"))
})
test("public reconnect checks capability and retains one map", async () => {
  const f = fixture()
  await f.owner.mount()
  await f.owner.reconnect()
  assert.equal(f.maps, 1)
  assert.equal(f.calls.filter((x) => x === "metadata").length, 4)
  f.owner.destroy()
})
test("changed public metadata drops a mixed grant completion", async () => {
  const f = fixture()
  let reads = 0
  f.reader.read = async (resource) => ({
    data:
      resource === "metadata"
        ? { ...config, photosEnabled: ++reads > 1 }
        : points,
  })
  assert.equal(await f.owner.mount(), "failed")
  assert.equal(f.renders, 0)
  assert.equal(f.photoLoads, 0)
  f.owner.destroy()
})
test("public replay snapshot uses public sampling and refuses private studios", async () => {
  const f = fixture()
  await f.owner.mount()
  const snapshot = await f.owner.source.snapshot({ purpose: "replay" })
  assert.equal(snapshot.points.length, 2)
  assert.equal(snapshot.points[0].longitude, 13)
  await assert.rejects(f.owner.source.snapshot({ purpose: "poster" }))
  assert.equal(f.owner.source.fixedRange, true)
  f.owner.destroy()
})

test("public route style restoration drops cleared geometry", async () => {
  const { createPublicLayers } = await import(
    "../../app-phoenix/assets/js/map/public/layers.js"
  )
  const sources = new Map(),
    layers = new Map(),
    handlers = new Map()
  const map = {
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    addSource: (id, value) => sources.set(id, value),
    removeSource: (id) => sources.delete(id),
    addLayer: (value) => layers.set(value.id, value),
    removeLayer: (id) => layers.delete(id),
    on: (event, fn) => handlers.set(event, fn),
    off: (event) => handlers.delete(event),
    fitBounds() {},
    isStyleLoaded: () => true,
  }
  const library = {
    LngLatBounds: class {
      extend() {
        return this
      }
    },
  }
  const owner = createPublicLayers({ map, library })
  owner.show({ points, route: [] }, config)
  assert.ok(sources.has("public-route"))
  sources.clear()
  layers.clear()
  handlers.get("style.load")()
  assert.ok(sources.has("public-route"))
  owner.clear()
  sources.clear()
  layers.clear()
  handlers.get("style.load")()
  assert.equal(sources.size, 0)
  owner.destroy()
  assert.equal(handlers.size, 0)
})

test("public photo factory is constructed only inside the active owner", async () => {
  const f = fixture()
  f.reader.read = async (resource) => ({
    data: resource === "metadata" ? { ...config, photosEnabled: true } : points,
  })
  assert.equal(await f.owner.mount(), "ready")
  assert.equal(f.photoLoads, 1)
  f.owner.destroy()
})

test("destroy during public photo factory acquisition releases its late owner", async () => {
  let resolve,
    released = 0,
    started
  const acquired = new Promise((r) => {
    resolve = r
  })
  const begun = new Promise((r) => {
    started = r
  })
  const f = fixture({
    loadPhotos: () => {
      started()
      return acquired
    },
  })
  f.reader.read = async (resource) => ({
    data: resource === "metadata" ? { ...config, photosEnabled: true } : points,
  })
  const pending = f.owner.mount()
  await begun
  f.owner.destroy()
  resolve({
    remove() {
      released++
    },
    add() {
      throw new Error("removed")
    },
  })
  assert.equal(await pending, "cancelled")
  await Promise.resolve()
  assert.equal(released, 1)
})

test("public replay refuses a grant range changed since the visible owner", async () => {
  const f = fixture()
  await f.owner.mount()
  f.reader.read = async (resource) => ({
    data:
      resource === "metadata"
        ? { ...config, range: { ...config.range, endAt: "2026-10-10" } }
        : points,
  })
  await assert.rejects(f.owner.source.snapshot({ purpose: "replay" }))
  f.owner.destroy()
})

test("public metadata updates retain localized photo labels", async () => {
  const labels = []
  const f = fixture({
    loadPhotos: async (options) => {
      labels.push(options.labels)
      return {
        add() {},
        remove() {},
        async load() {
          return "ready"
        },
      }
    },
  })
  f.reader.read = async (resource) => ({
    data: resource === "metadata" ? { ...config, photosEnabled: true } : points,
  })
  await f.owner.mount()
  const { photoLabels: _labels, ...next } = config
  await f.owner.update({ ...next, revision: 2 })
  assert.equal(labels.at(-1)["map_info.photo"], "Foto")
  f.owner.destroy()
})

test("native public replay uses its scoped source and closes marker ownership", async () => {
  const f = fixture()
  await f.owner.mount()
  const sources = new Map(),
    layers = new Map()
  Object.assign(f.owner.map, {
    getSource: (id) => sources.get(id),
    addSource: (id, value) =>
      sources.set(id, {
        ...value,
        setData(data) {
          this.data = data
        },
      }),
    removeSource: (id) => sources.delete(id),
    getLayer: (id) => layers.get(id),
    addLayer: (layer) => layers.set(layer.id, layer),
    removeLayer: (id) => layers.delete(id),
    on() {},
  })
  await f.owner.replay.open()
  assert.equal(sources.has("native-replay-marker"), true)
  f.owner.replay.close()
  assert.equal(sources.has("native-replay-marker"), false)
  f.owner.destroy()
})
