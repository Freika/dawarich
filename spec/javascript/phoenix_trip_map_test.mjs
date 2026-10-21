import assert from "node:assert/strict"
import { test } from "node:test"
import { createReader } from "../../app-phoenix/assets/js/map/data/reader.js"
import { mountTrip } from "../../app-phoenix/assets/js/map/trip/runtime.js"

const defer = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const start = "2026-04-20T00:00:00Z",
  end = "2026-04-21T00:00:00Z"
const metadata = {
  config: {
    tripId: 7,
    title: "Owned trip",
    range: { startAt: start, endAt: end, timezone: "UTC" },
    routeOptions: { timeThresholdMinutes: 60, distanceThresholdMeters: 500 },
    photosEnabled: false,
    planEnabled: false,
  },
  deviceWindows: [],
  path: [
    [13, 52],
    [14, 53],
  ],
  plan: null,
}
const points = [
  {
    id: 1,
    timestamp: Date.parse("2026-04-20T10:00Z") / 1000,
    latitude: 52,
    longitude: 13,
  },
  {
    id: 2,
    timestamp: Date.parse("2026-04-20T11:00Z") / 1000,
    latitude: 53,
    longitude: 14,
  },
]
const flights = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates: [
          [13, 52],
          [14, 53],
        ],
      },
      properties: {
        id: 3,
        departure_time: "2026-04-20T09:00:00Z",
        arrival_time: "2026-04-20T12:00:00Z",
      },
    },
  ],
}
function fixture(config = {}, options = {}) {
  let releaseLoad, lastUpdate
  let maps = 0,
    removed = 0,
    updates = 0,
    disposed = 0
  const reads = []
  const element = {
    dataset: {
      mapConfig: JSON.stringify({
        revision: 1,
        tripId: 7,
        range: metadata.config.range,
        flightsEnabled: true,
        mapOptions: {},
        ...config,
      }),
    },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const reader = options.reader ?? {
    read: async (resource, params, options) => {
      reads.push({ resource, params, options })
      return { data: resource === "trip" ? structuredClone(metadata) : flights }
    },
    pages: async (resource, params, options) => {
      reads.push({ resource, params, options })
      return points
    },
    reset() {},
    destroy() {
      this.destroyed = true
    },
  }
  const library = {
    Map: class {
      constructor() {
        maps++
      }
      loaded() {
        return options.loaded ?? true
      }
      once(_event, callback) {
        releaseLoad = callback
      }
      remove() {
        removed++
      }
      off() {}
    },
  }
  const layers = {
    update(data, snapshot, config) {
      lastUpdate = { data, snapshot, config }
      updates++
    },
    destroy() {
      disposed++
    },
    selectDay() {},
    days: { getDayColor: (day) => day === "2026-04-20" ? "#6366F1" : undefined },
  }
  const owner = mountTrip({
    element,
    reader,
    pushEvent() {},
    loadLibrary: async () => library,
    loadStyle: async () => ({}),
    createLayers: () => layers,
  })
  return {
    owner,
    releaseLoad: () => releaseLoad(),
    get lastUpdate() {
      return lastUpdate
    },
    reader,
    reads,
    element,
    library,
    get maps() {
      return maps
    },
    get removed() {
      return removed
    },
    get updates() {
      return updates
    },
    get disposed() {
      return disposed
    },
  }
}
test("trip destroy during point or style fetch cannot create or repaint a map", async () => {
  const f = fixture()
  const style = defer()
  const owner = mountTrip({
    element: f.element,
    reader: f.reader,
    pushEvent() {},
    loadLibrary: async () => f.library,
    loadStyle: () => style.promise,
    createLayers: () => ({
      update() {
        throw new Error("late update")
      },
      destroy() {},
    }),
  })
  const mounting = owner.mount()
  await Promise.resolve()
  owner.destroy()
  style.resolve({})
  assert.equal(await mounting, "cancelled")
  assert.equal(f.maps, 0)
  const g = fixture()
  const late = defer()
  g.reader.pages = () => late.promise
  const pending = g.owner.mount()
  await new Promise((r) => setImmediate(r))
  assert.equal(g.maps, 1)
  const before = g.updates
  g.owner.destroy()
  late.resolve(points)
  assert.equal(await pending, "cancelled")
  assert.equal(g.updates, before)
  assert.equal(g.disposed, 1)
  assert.equal(g.removed, 1)
})
test("trip studios remain locked to owned trip range and fresh device windows", async () => {
  const f = fixture()
  await f.owner.mount()
  const snapshot = await f.owner.source.snapshot({ purpose: "video" })
  assert.deepEqual(snapshot.range, metadata.config.range)
  assert.equal(f.owner.source.fixedRange, true)
  await assert.rejects(
    f.owner.source.applyDates({ startAt: "1900-01-01" }),
    /fixed/,
  )
  assert.equal(
    f.reads
      .filter((r) => r.resource === "points")
      .every((r) => r.params.start_at === start && r.params.end_at === end),
    true,
  )
  await f.owner.reconnect()
  assert.equal(f.maps, 1)
  f.owner.destroy()
})
test("trip poster uses visible flight arcs while video uses timed GPS", async () => {
  const f = fixture()
  await f.owner.mount()
  const poster = await f.owner.source.snapshot({ purpose: "poster" })
  const video = await f.owner.source.snapshot({ purpose: "video" })
  assert.equal(
    poster.geojson.features.some((row) => row.properties.id === 3),
    true,
  )
  assert.equal(
    video.geojson.features.some((row) => row.properties.id === 3),
    false,
  )
  assert.deepEqual(video.points, points)
  f.owner.destroy()
})

test("trip configuration revision invalidates a pending studio snapshot", async () => {
  const f = fixture()
  await f.owner.mount()
  const late = defer()
  f.reader.pages = () => late.promise
  const snapshot = f.owner.source.snapshot({ purpose: "video" })
  await new Promise((r) => setImmediate(r))
  const admission = defer()
  f.reader.read = () => admission.promise
  const updating = f.owner.update({ ...f.owner.config, revision: 2 })
  try {
    late.resolve(points)
    await assert.rejects(snapshot, (e) => e.name === "AbortError")
  } finally {
    f.owner.destroy()
    admission.resolve({ data: metadata })
    await updating
  }
})

test("native trip replay uses its scoped source and closes marker ownership", async () => {
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

test("trip replay acquires one photo window through its scoped snapshot", async () => {
  const f = fixture({ photosEnabled: true })
  const snapshot = await f.owner.source.snapshot({ purpose: "replay" })
  assert.equal(snapshot.photos.length, 2)
  const calls = f.reads.filter((read) => read.resource === "photos")
  assert.equal(calls.length, 1)
  assert.deepEqual(calls[0].params, { start_date: start, end_date: end })
  f.owner.destroy()
})

test("trip launcher dispatches its fixed stable source and releases the click owner", async () => {
  const f = fixture()
  const { Element } = await import("./support/native_m6_host_fixture.mjs")
  const root = new Element(),
    button = new Element(),
    studio = new Element()
  const events = []
  globalThis.CustomEvent ??= class {
    constructor(type, options) {
      this.type = type
      Object.assign(this, options)
    }
  }
  root.querySelector = (selector) =>
    selector === '[data-testid="map-button-video"]'
      ? button
      : selector === "#native-video-studio"
        ? studio
        : null
  root.contains = (node) => node === button
  button.closest = (selector) =>
    selector === "[data-native-map-root]"
      ? root
      : selector === '[data-testid="map-button-video"]'
        ? button
        : null
  studio.dispatchEvent = (event) => events.push(event)
  button.parent = root
  button.selector = '[data-testid="map-button-video"]'
  f.element.closest = () => root
  await f.owner.mount()
  root.emit("click", { target: button })
  assert.equal(events[0].detail.source, f.owner.source)
  assert.equal(events[0].detail.source.fixedRange, true)
  f.owner.destroy()
  root.emit("click", { target: button })
  assert.equal(events.length, 1)
})

test("trip document publishes readiness failure and disposal through its native owner", async () => {
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

test("Trip config and reconnect wait for attachment then paint latest geometry once", async () => {
  const f = fixture({}, { loaded: false })
  try {
    const mounting = f.owner.mount()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.maps, 1)
    const next = { ...f.owner.config, tripId: 9, revision: 2 }
    const updating = f.owner.update(next)
    const reconnecting = f.owner.reconnect()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.reads.length, 0)
    f.releaseLoad()
    assert.deepEqual(await Promise.all([mounting, updating, reconnecting]), [
      "ready",
      "ready",
      "ready",
    ])
    assert.equal(f.maps, 1)
    assert.equal(f.reads.find((read) => read.resource === "trip").params.id, 9)
    assert.deepEqual(f.lastUpdate.snapshot.points, points)
    assert.equal(f.lastUpdate.config.revision, 2)
    assert.equal(f.updates, 2)
  } finally {
    f.owner.destroy()
  }
})

test("trip refresh preserves a pending replay snapshot and panel opening", async () => {
  const pending = defer()
  const requested = defer()
  let hold = false
  const reader = createReader({
    origin: "https://native.test",
    fetch: async (url) => {
      const resource = new URL(url).pathname.split("/").at(-1)
      if (hold && resource === "7") {
        requested.resolve()
        await pending.promise
      }
      return new Response(JSON.stringify(
        resource === "7" ? metadata : resource === "points" ? points : flights,
      ), { headers: { "x-total-pages": "1" } })
    },
  })
  const fork = reader.fork
  let snapshotReader
  reader.fork = () => (snapshotReader = fork())
  const f = fixture({}, { reader })
  const { Element } = await import("./support/native_m6_host_fixture.mjs")
  const root = new Element(), panel = new Element()
  panel.hidden = true
  root.querySelector = selector => selector === "[data-native-replay-panel]" ? panel : null
  f.element.closest = () => root
  try {
    assert.equal(await f.owner.mount(), "ready")
    const sources = new Map(), layers = new Map()
    Object.assign(f.owner.map, {
      getSource: id => sources.get(id),
      addSource: (id, value) => sources.set(id, { ...value, setData() {} }),
      removeSource: id => sources.delete(id),
      getLayer: id => layers.get(id),
      addLayer: layer => layers.set(layer.id, layer),
      removeLayer: id => layers.delete(id),
      on() {},
    })
    hold = true
    const opening = f.owner.replay.open()
    await requested.promise
    const generation = reader.revision
    const updating = f.owner.reconnect()
    pending.resolve()
    assert.equal(await opening, "ready")
    assert.equal(await updating, "ready")
    assert.equal(reader.revision, generation + 1)
    assert.equal(panel.hidden, false)
    assert.equal(sources.has("native-replay-marker"), true)
  } finally {
    pending.resolve()
    f.owner.destroy()
  }
  assert.equal(snapshotReader.revision, 1)
})

test("loaded trip day colors reach the matching accordion dots", async () => {
  const f = fixture()
  const dots = ["2026-04-20", "2026-04-21"].map(day => ({ dataset: { dayDot: day }, style: {} }))
  const { Element } = await import("./support/native_m6_host_fixture.mjs")
  const root = new Element()
  root.querySelector = () => null
  root.querySelectorAll = (selector) => selector === "[data-day-dot]" ? dots : []
  f.element.closest = () => root
  assert.equal(await f.owner.mount(), "ready")
  assert.equal(dots[0].style.backgroundColor, "#6366F1")
  assert.equal(dots[1].style.backgroundColor, undefined)
  f.owner.destroy()
})
