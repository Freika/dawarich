import assert from "node:assert/strict"
import { test } from "node:test"
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
function fixture() {
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
      }),
    },
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const reader = {
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
        return true
      }
      remove() {
        removed++
      }
      off() {}
    },
  }
  const layers = {
    update() {
      updates++
    },
    destroy() {
      disposed++
    },
    selectDay() {},
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
  const sources = new Map(), layers = new Map()
  Object.assign(f.owner.map, {
    getSource: id => sources.get(id), addSource: (id, value) => sources.set(id, {...value, setData(data) {this.data=data}}), removeSource: id => sources.delete(id),
    getLayer: id => layers.get(id), addLayer: layer => layers.set(layer.id, layer), removeLayer: id => layers.delete(id), on() {},
  })
  await f.owner.replay.open()
  assert.equal(sources.has("native-replay-marker"), true)
  f.owner.replay.close()
  assert.equal(sources.has("native-replay-marker"), false)
  f.owner.destroy()
})
