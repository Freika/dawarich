import assert from "node:assert/strict"
import { test } from "node:test"
import {
  createPhotoLoader,
  photosToGeoJSON,
} from "../../app-phoenix/assets/js/map/data/photo_loader.js"
import { PhotoSpider } from "../../app-phoenix/assets/js/map/layers/photo_spider.js"
import { PhotosLayer } from "../../app-phoenix/assets/js/map/layers/photos.js"
import { createPhotoMarker } from "../../app-phoenix/assets/js/map/ui/photo_marker.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const photo = {
  id: "synthetic-photo",
  latitude: 52,
  longitude: 13,
  capturedAt: "2026-03-29T01:00:00Z",
  originalFileName: "<script>photo</script>",
  source: "immich",
}
const range = { startAt: "2026-03-29", endAt: "2026-03-30" }
function clock() {
  const timers = new Map()
  let id = 0
  return {
    timers,
    setTimeout(fn) {
      timers.set(++id, fn)
      return id
    },
    clearTimeout(id) {
      timers.delete(id)
    },
    expire() {
      for (const fn of [...timers.values()]) fn()
    },
  }
}

test("timed-out or replaced photo load cannot add a marker", async () => {
  const timers = clock(),
    old = deferred(),
    latest = deferred()
  let request = 0,
    signal
  const commits = [],
    errors = []
  const loader = createPhotoLoader({
    reader: {
      pages(_kind, params, options) {
        assert.deepEqual(params, {
          start_date: range.startAt,
          end_date: range.endAt,
        })
        signal = options.signal
        return ++request === 1 ? old.promise : latest.promise
      },
    },
    timers,
    onData: (d) => commits.push(d),
    onError: (code) => errors.push(code),
  })
  const first = loader.load(range)
  const firstSignal = signal
  const second = loader.load(range)
  assert.equal(firstSignal.aborted, true)
  latest.resolve([photo])
  assert.equal(await second, "ready")
  old.resolve([{ ...photo, id: "stale" }])
  assert.equal(await first, "cancelled")
  assert.equal(commits.length, 1)
  assert.equal(commits[0].features[0].properties.id, photo.id)
  assert.equal(timers.timers.size, 0)
  const expired = loader.load(range)
  timers.expire()
  assert.equal(await expired, "failed")
  assert.equal(errors.at(-1), "photos_load_failed")
  loader.destroy()
  assert.equal(timers.timers.size, 0)
})

test("photo rows preserve empty and zero-coordinate filtering with metadata", () => {
  assert.deepEqual(photosToGeoJSON([]).features, [])
  const rows = photosToGeoJSON([
    photo,
    { ...photo, latitude: 0 },
    { ...photo, longitude: 0 },
    { ...photo, latitude: null },
  ]).features
  assert.equal(rows.length, 1)
  assert.deepEqual(rows[0].geometry.coordinates, [13, 52])
  assert.equal(rows[0].properties.filename, photo.originalFileName)
  assert.equal(rows[0].properties.thumbnail_url, undefined)
})

function fixture() {
  const elements = [],
    popups = [],
    markers = [],
    events = new Map(),
    sources = new Map(),
    layers = new Map(),
    urls = new Set()
  let created = 0
  const document = {
    documentElement: {
      getAttribute: () => "light",
      classList: { contains: () => false },
    },
    createElement() {
      const element = {
        style: {},
        events: new Map(),
        appendChild() {},
        addEventListener(k, fn) {
          this.events.set(k, fn)
        },
        removeEventListener(k, fn) {
          if (this.events.get(k) === fn) this.events.delete(k)
        },
      }
      elements.push(element)
      return element
    },
  }
  class Marker {
    constructor({ element }) {
      this.element = element
      markers.push(this)
    }
    setLngLat(value) {
      this.position = value
      return this
    }
    addTo() {
      return this
    }
    getElement() {
      return this.element
    }
    remove() {
      this.removed = true
    }
  }
  class Popup {
    constructor() {
      popups.push(this)
      this.events = new Map()
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
    on(k, fn) {
      this.events.set(k, fn)
      return this
    }
    off(k) {
      this.events.delete(k)
      return this
    }
    remove() {
      this.removed = true
      for (const fn of this.events.values()) fn()
      return this
    }
  }
  const map = {
    getContainer: () => ({ ownerDocument: document }),
    getCanvas: () => ({ style: {} }),
    getBounds: () => ({ contains: () => true }),
    getMaxZoom: () => 16,
    easeTo(value) {
      this.eased = value
    },
    project: ([lng, lat]) => ({ x: lng, y: lat }),
    unproject: ([x, y]) => ({ lng: x, lat: y }),
    querySourceFeatures: () => [photosToGeoJSON([photo]).features[0]],
    queryRenderedFeatures: () => [
      { properties: { cluster_id: 1 }, geometry: { coordinates: [13, 52] } },
    ],
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
    addLayer(layer) {
      layers.set(layer.id, layer)
    },
    removeSource(id) {
      sources.delete(id)
    },
    removeLayer(id) {
      layers.delete(id)
    },
    setLayoutProperty() {},
    on(k, layer, fn) {
      events.set(k, new Set([...(events.get(k) ?? []), fn ?? layer]))
    },
    off(k, layer, fn) {
      events.get(k)?.delete(fn ?? layer)
    },
    emit(k) {
      for (const fn of events.get(k) ?? []) fn()
    },
  }
  return {
    document,
    library: { Marker, Popup },
    map,
    sources,
    layers,
    events,
    elements,
    popups,
    markers,
    urls,
    URL: {
      createObjectURL() {
        const url = `blob:synthetic-${++created}`
        urls.add(url)
        return url
      },
      revokeObjectURL(url) {
        urls.delete(url)
      },
    },
  }
}

test("destroy releases popup listeners and thumbnails", async () => {
  const f = fixture(),
    pending = deferred()
  let signal
  const marker = createPhotoMarker({
    ...f,
    feature: photosToGeoJSON([photo]).features[0],
    reader: {
      read(kind, params, options) {
        assert.equal(kind, "thumbnail")
        assert.deepEqual(params, { id: photo.id, source: "immich" })
        signal = options.signal
        return pending.promise
      },
    },
  })
  pending.resolve({
    data: new Blob(["synthetic-image"], { type: "image/jpeg" }),
  })
  await marker.ready
  assert.equal(f.urls.size, 1)
  assert.equal(signal.aborted, false)
  f.elements[1].events.get("click")({ stopPropagation() {} })
  assert.equal(f.popups.length, 1)
  assert.ok(f.popups[0].html.includes("&lt;script&gt;photo&lt;/script&gt;"))
  assert.ok(!f.popups[0].html.includes("<script>"))
  assert.ok(f.popups[0].html.includes("blob:synthetic"))
  marker.remove()
  marker.remove()
  assert.equal(f.urls.size, 0)
  assert.equal(f.popups[0].removed, true)
  assert.ok(f.elements.every((el) => el.events.size === 0))
  assert.equal(f.popups[0].events.size, 0)
})

test("late thumbnail and cluster callbacks cannot allocate after photo owner removal", async () => {
  const f = fixture(),
    bytes = deferred(),
    expansion = deferred(),
    leaves = deferred()
  const layer = new PhotosLayer(f.map, {
    ...f,
    reader: { read: () => bytes.promise },
  })
  layer.add(photosToGeoJSON([photo]))
  const source = f.sources.get(layer.sourceId)
  source.getClusterExpansionZoom = () => expansion.promise
  source.getClusterLeaves = () => leaves.promise
  const cluster = layer.expand({ point: [1, 1] })
  expansion.resolve(20)
  for (let i = 0; i < 8; i++) await Promise.resolve()
  layer.remove()
  leaves.resolve([photosToGeoJSON([photo]).features[0]])
  bytes.resolve({ data: new Blob(["synthetic"]) })
  await cluster
  for (let i = 0; i < 12; i++) await Promise.resolve()
  assert.equal(f.urls.size, 0)
  assert.ok(f.markers.every((m) => m.removed))
  assert.equal(f.markers.length, 1)
  assert.equal(f.map.eased, undefined)
  assert.equal(f.sources.size, 0)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})

test("photo style replacement restores one listener set and overlap rings preserve every leaf", async () => {
  const f = fixture()
  const layer = new PhotosLayer(f.map, {
    ...f,
    reader: { read: async () => ({ data: new Blob(["synthetic"]) }) },
  })
  layer.add(photosToGeoJSON([photo]))
  f.sources.clear()
  f.layers.clear()
  f.map.emit("style.load")
  f.map.emit("style.load")
  assert.equal(f.sources.size, 1)
  assert.equal(f.layers.size, 2)
  assert.equal(f.events.get("moveend").size, 1)
  const spider = new PhotoSpider(f.map, () => {})
  for (const count of [1, 8, 9, 60]) {
    const positions = spider._computeSpiralPositions(count, { x: 0, y: 0 })
    assert.equal(positions.length, count)
    assert.equal(new Set(positions.map((p) => `${p.x},${p.y}`)).size, count)
  }
  layer.remove()
  for (let i = 0; i < 12; i++) await Promise.resolve()
  assert.equal(f.urls.size, 0)
})

test("thumbnail timeout aborts only its read and drops later image bytes", async () => {
  const f = fixture(),
    timers = clock(),
    pending = deferred(),
    errors = []
  let signal
  const marker = createPhotoMarker({
    ...f,
    timers,
    feature: photosToGeoJSON([photo]).features[0],
    onError: (code) => errors.push(code),
    reader: {
      read(_kind, _params, options) {
        signal = options.signal
        return pending.promise
      },
    },
  })
  timers.expire()
  await marker.ready
  assert.equal(signal.aborted, true)
  assert.deepEqual(errors, ["photo_thumbnail_failed"])
  pending.resolve({ data: new Blob(["stale bytes"]) })
  for (let i = 0; i < 12; i++) await Promise.resolve()
  assert.equal(f.urls.size, 0)
  assert.equal(timers.timers.size, 0)
  marker.remove()
})

test("partial photo sources retain visible rows and a bounded warning", async () => {
  const errors = [],
    commits = []
  const loader = createPhotoLoader({
    reader: {
      pages: async (_kind, _params, options) => {
        options.onPage({
          headers: new Headers({ "x-photo-source-errors": "photoprism" }),
        })
        return [photo]
      },
    },
    onData: (data) => commits.push(data),
    onError: (code) => errors.push(code),
  })
  assert.equal(await loader.load(range), "ready")
  assert.equal(commits[0].features.length, 1)
  assert.deepEqual(errors, ["photo_sources_partial"])
  loader.destroy()
})

test("photo load pages the complete bounded cookie window before publishing", async () => {
  const { createReader } = await import(
    "../../app-phoenix/assets/js/map/data/reader.js"
  )
  const requests = [],
    warnings = [],
    commits = []
  const reader = createReader({
    origin: "https://map.test",
    fetch: async (url) => {
      const query = new URL(url).searchParams
      assert.equal(query.get("start_date"), range.startAt)
      assert.equal(query.get("end_date"), range.endAt)
      assert.equal(query.get("per_page"), "1000")
      requests.push(query.get("page"))
      return new Response(
        JSON.stringify([{ ...photo, id: `page-${query.get("page")}` }]),
        {
          headers: {
            "x-total-pages": "2",
            "x-photo-source-errors": "photoprism",
          },
        },
      )
    },
  })
  const loader = createPhotoLoader({
    reader,
    onData: (data) => commits.push(data),
    onError: (code) => warnings.push(code),
  })
  assert.equal(await loader.load(range), "ready")
  assert.deepEqual(requests, ["1", "2"])
  assert.equal(commits.length, 1)
  assert.equal(commits[0].features.length, 2)
  assert.deepEqual(warnings, ["photo_sources_partial"])
  loader.destroy()
  reader.destroy()
})

test("native photo host is lazy and disposal releases every loaded thumbnail", async () => {
  const { mountHost } = await import(
    "../../app-phoenix/assets/js/map/runtime/host.js"
  )
  const f = fixture()
  let photoReads = 0,
    closed = 0,
    removed = 0
  const config = {
    range,
    revision: 1,
    photosEnabled: false,
    pointsEnabled: true,
  }
  f.map.querySourceFeatures = (id) => f.sources.get(id)?.data?.features ?? []
  Object.assign(f.map, {
    loaded: () => true,
    remove: () => removed++,
    getStyle: () => ({ layers: [] }),
    setFilter() {},
    setPaintProperty() {},
  })
  const reader = {
    reset() {},
    destroy() {
      closed++
    },
    async pages(kind) {
      assert.equal(kind, "photos")
      photoReads++
      return [photo]
    },
    async read(kind) {
      assert.equal(kind, "thumbnail")
      return { data: new Blob(["synthetic"], { type: "image/jpeg" }) }
    },
  }
  const element = {
    dataset: { mapConfig: JSON.stringify(config) },
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
    pushEvent() {},
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    loadLibrary: async () => ({ ...f.library, Map: FakeMap }),
  })
  assert.equal(await owner.mount(), "ready")
  assert.equal(photoReads, 0)
  assert.equal(await owner.update({ ...config, photosEnabled: true }), "ready")
  for (let i = 0; i < 12; i++) await Promise.resolve()
  assert.equal(photoReads, 1)
  assert.equal(f.markers.length, 1)
  assert.equal(f.markers[0].removed, undefined)
  assert.equal(await owner.reconnect(), "ready")
  assert.equal(photoReads, 1)
  owner.destroy()
  assert.ok(f.markers.every((marker) => marker.removed))
  assert.equal(closed, 1)
  assert.equal(removed, 1)
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})

test("unconfigured photo integration is distinct from an unauthorized read", async () => {
  for (const code of ["photos_unconfigured", undefined]) {
    const errors = []
    const loader = createPhotoLoader({
      reader: {
        pages: async () => {
          throw Object.assign(new Error("read failed"), { status: 401, code })
        },
      },
      onError: (error) => errors.push(error),
    })
    assert.equal(await loader.load(range), code ? "unconfigured" : "failed")
    assert.deepEqual(errors, [
      code ? "photos_unconfigured" : "photos_load_failed",
    ])
    loader.destroy()
  }
})
