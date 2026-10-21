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
    element,
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

test("public document publishes readiness failure and disposal through its native owner", async () => {
  const f = fixture()
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.equal(f.element.dataset.mapState, "ready")
    f.reader.read = async () => {
      throw new Error("Synthetic read failure")
    }
    assert.equal(await f.owner.reconnect(), "failed")
    assert.equal(f.element.dataset.mapState, "failed")
  } finally {
    f.owner.destroy()
  }
  assert.equal(f.element.dataset.mapState, "cancelled")
})

test("current public map refresh deadline ends loading clears data emits failure and rejects late geometry", async () => {
  const jobs = new Map()
  let next = 0,
    release
  const timers = {
    setTimeout(fn) {
      jobs.set(++next, fn)
      return next
    },
    clearTimeout(id) {
      jobs.delete(id)
    },
  }
  const f = fixture({ timers })
  try {
    await f.owner.mount()
    const read = f.reader.read
    f.reader.read = async (resource) =>
      resource === "metadata"
        ? { data: config }
        : new Promise((resolve) => {
            release = resolve
          })
    const refreshing = f.owner.reconnect()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.element.dataset.mapState, "loading")
    assert.equal(jobs.size, 1)
    const expire = [...jobs.values()].at(-1)
    expire()
    assert.equal(await refreshing, "failed")
    assert.equal(f.element.dataset.mapState, "failed")
    assert.equal(f.cleared, 2)
    assert.deepEqual(f.events.at(-1), [
      "map:failed",
      { code: "map_refresh_failed" },
    ])
    release({ data: points })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.renders, 1)
    f.reader.read = read
    assert.equal(await f.owner.reconnect(), "ready")
    assert.equal(f.renders, 2)
    assert.equal(f.maps, 1)
  } finally {
    release?.({ data: points })
    f.owner.destroy()
  }
  assert.equal(jobs.size, 0)
})

test("public refresh accepts renewed read leases but refuses shortened deadlines", async () => {
  const f = fixture()
  let reads = 0
  f.reader.read = async (resource) => ({
    data:
      resource === "metadata"
        ? {
            ...config,
            validUntil:
              ++reads === 1 ? "2026-10-12T00:00:00Z" : "2026-10-12T00:00:01Z",
          }
        : points,
  })
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.equal(f.renders, 1)
    reads = 0
    f.reader.read = async (resource) => ({
      data:
        resource === "metadata"
          ? {
              ...config,
              validUntil:
                ++reads === 1 ? "2026-10-12T00:00:01Z" : "2026-10-12T00:00:00Z",
            }
          : points,
    })
    assert.equal(await f.owner.reconnect(), "failed")
    assert.equal(f.renders, 1)
  } finally {
    f.owner.destroy()
  }
})

test("public runtime owns local day hover without extra reads and stops it after refusal or destroy", async () => {
  const root = new EventTarget()
  root.querySelector = () => null
  root.querySelectorAll = () => []
  const selected = [],
    pins = [],
    previews = []
  const f = fixture({
    createLayers: () => ({
      show() {},
      clear() {},
      destroy() {},
      selectDay: (day) => {
        pins.push(day)
        selected.push(day)
      },
      previewDay: (day) => {
        previews.push(day)
        selected.push(day)
      },
      getDayColor: () => "#6366f1",
    }),
  })
  f.element.closest = () => root
  function hover(type, day) {
    const row = { dataset: { publicDay: day }, closest: () => root }
    const event = new Event(type)
    Object.defineProperty(event, "target", { value: { closest: () => row } })
    root.dispatchEvent(event)
  }
  await f.owner.mount()
  const reads = f.calls.length
  f.owner.selectDay("2026-10-08")
  hover("mouseover", "2026-10-09")
  hover("mouseout", "2026-10-09")
  assert.deepEqual(selected, ["2026-10-08", "2026-10-09", "2026-10-08"])
  assert.deepEqual(pins, ["2026-10-08"])
  assert.deepEqual(previews, ["2026-10-09", "2026-10-08"])
  assert.equal(f.calls.length, reads)
  f.reader.read = async () => {
    throw new Error("revoked")
  }
  assert.equal(await f.owner.reconnect(), "failed")
  hover("mouseover", "2026-10-09")
  assert.equal(selected.length, 3)
  f.owner.destroy()
  hover("mouseover", "2026-10-09")
  assert.equal(selected.length, 3)
})

test("public day preview preserves the viewport and ignores days without route data", async () => {
  const { createPublicLayers } = await import(
    "../../app-phoenix/assets/js/map/public/layers.js"
  )
  const sources = new Map(),
    layers = new Map(),
    fits = [],
    paint = []
  const map = {
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    addSource: (id, value) => sources.set(id, value),
    removeSource: (id) => sources.delete(id),
    addLayer: (value) => layers.set(value.id, value),
    removeLayer: (id) => layers.delete(id),
    on() {},
    off() {},
    getCanvas: () => ({ style: {} }),
    fitBounds: (...args) => fits.push(args),
    setPaintProperty: (...args) => paint.push(args),
    isStyleLoaded: () => true,
  }
  const library = {
    LngLatBounds: class {
      constructor() {
        this.points = []
      }
      extend(point) {
        this.points.push(point)
        return this
      }
      isEmpty() {
        return this.points.length === 0
      }
    },
  }
  const owner = createPublicLayers({ map, library })
  owner.show(
    { points: [points[0], [13.001, 52.001, points[0][2] + 20]], route: [] },
    { ...config, byDay: true },
  )
  const day = new Date(points[0][2] * 1000).toISOString().slice(0, 10)
  const beforeFits = fits.length
  assert.equal(owner.previewDay(day), true)
  assert.ok(paint.length > 0)
  assert.equal(fits.length, beforeFits)
  const beforePaint = paint.length
  assert.equal(owner.previewDay("2026-01-01"), false)
  assert.equal(paint.length, beforePaint)
  assert.equal(owner.selectDay("2026-01-01"), false)
  assert.equal(fits.length, beforeFits)
  assert.equal(owner.selectDay(day), true)
  assert.equal(fits.length, beforeFits + 1)
  owner.destroy()
})
