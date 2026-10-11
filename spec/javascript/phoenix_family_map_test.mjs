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
function fixture(options = {}) {
  let releaseLoad
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
      return options.loaded ?? true
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
      if (e === "load") releaseLoad = f
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
    ...options.timers,
  }
  const empty = { hidden: false, style: {} }
  const element = {
    querySelector: (selector) =>
      selector === "[data-family-empty]" ? empty : null,
    dataset: {
      mapConfig: JSON.stringify({
        revision: 1,
        consentLeaseMs: options.consentLeaseMs ?? 30000,
        locale: "de",
        range: { startAt: "2026-10-01", endAt: "2026-10-04" },
        mapOptions: {},
      }),
    },
    ownerDocument: { defaultView: options.window, createElement: () => ({ style: {}, remove() {} }) },
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
    now: options.now,
    isOffline: options.isOffline,
    loadLibrary: async () => ({ Map: MapView, Popup }),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    pushEvent() {},
  })
  return {
    owner,
    releaseLoad: () => releaseLoad(),
    empty,
    reader,
    element,
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

test("family locale replacement refreshes popup formatting without another map", async () => {
  const f = fixture()
  await f.owner.mount()
  await f.owner.update({ ...f.owner.config, locale: "en" })
  for (const fn of f.events.get("click:family-circles"))
    fn({ features: [{ properties: { id: 7 } }], lngLat: [13, 52] })
  assert.match(f.popups.at(-1).html, /ago/)
  assert.equal(f.maps, 1)
  assert.equal(f.intervals.size, 1)
  f.owner.destroy()
})

test("family document publishes readiness failure and disposal through its native owner", async () => {
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

test("family empty guidance follows admitted locations and clears on withdrawal", async () => {
  const f = fixture()
  try {
    await f.owner.mount()
    assert.equal(f.empty.hidden, true)
    const admittedRead = f.reader.read
    f.reader.read = async (resource) => ({
      data:
        resource === "family_locations" ? { locations: [] } : { members: [] },
    })
    await f.owner.reconnect()
    assert.equal(f.empty.hidden, false)
    f.reader.read = admittedRead
    await f.owner.reconnect()
    assert.equal(f.empty.hidden, true)
    f.owner.clear()
    assert.equal(f.empty.hidden, false)
  } finally {
    f.owner.destroy()
  }
})

test("Family config and reconnect wait for attachment then paint latest geometry once", async () => {
  const f = fixture({ loaded: false })
  try {
    const mounting = f.owner.mount()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.maps, 1)
    const range = { startAt: "2026-10-05", endAt: "2026-10-06" }
    const updating = f.owner.update({ ...f.owner.config, revision: 2, range })
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
    assert.equal(f.reads.length, 2)
    assert.deepEqual(
      f.reads.find((read) => read.resource === "family_history").params,
      { start_at: range.startAt, end_at: range.endAt },
    )
    assert.equal(f.sources.get("family-members").data.features.length, 1)
  } finally {
    f.owner.destroy()
  }
})

test("idle Family consent expiry clears coordinates popups and late reads without manual reconnect", async () => {
  let time = 1000,
    next = 0
  const jobs = new Map()
  const f = fixture({
    consentLeaseMs: 100,
    now: () => time,
    timers: {
      setTimeout(fn, delay) {
        jobs.set(++next, { fn, delay })
        return next
      },
      clearTimeout(id) {
        jobs.delete(id)
      },
    },
  })
  try {
    await f.owner.mount()
    for (const fn of f.events.get("click:family-circles"))
      fn({ features: [{ properties: { id: 7 } }], lngLat: [13, 52] })
    const delayed = defer()
    f.reader.read = () => delayed.promise
    time += 100
    const expiry = [...jobs.values()].find((job) => job.delay === 100)
    assert.ok(expiry)
    expiry.fn()
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    assert.equal(f.sources.get("family-history").data.features.length, 0)
    assert.equal(f.popups[0].removed, true)
    f.reader.read = async (resource) => ({
      data:
        resource === "family_locations" ? { locations: [] } : { members: [] },
    })
    f.owner.lease({ milliseconds: 100 })
    const renewed = [...jobs.values()].find((job) => job.delay === 100)
    time += 100
    renewed.fn()
    delayed.resolve({
      data: {
        locations: [{ user_id: 7, latitude: 52, longitude: 13 }],
        members: [],
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    assert.equal(f.sources.get("family-history").data.features.length, 0)
    assert.equal(f.maps, 1)
  } finally {
    f.owner.destroy()
  }
  assert.equal(jobs.size, 0)
})

test("idle Family withdrawal is revalidated within the bounded lease and destroyed leases cannot refetch", async () => {
  let next = 0
  const jobs = new Map()
  const f = fixture({
    timers: {
      setTimeout(fn, delay) {
        jobs.set(++next, { fn, delay })
        return next
      },
      clearTimeout(id) {
        jobs.delete(id)
      },
    },
  })
  let expiry,
    revalidations = 0
  try {
    await f.owner.mount()
    f.reader.read = async (resource) => {
      revalidations++
      return {
        data:
          resource === "family_locations" ? { locations: [] } : { members: [] },
      }
    }
    expiry = [...jobs.values()].find(
      (job) => job.delay <= 30000 && job.delay > 15000,
    )
    assert.ok(expiry)
    expiry.fn()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    assert.equal(f.empty.hidden, false)
    assert.equal(revalidations, 2)
  } finally {
    f.owner.destroy()
  }
  const before = f.reads.length
  expiry.fn()
  await Promise.resolve()
  assert.equal(f.reads.length, before)
  assert.equal(jobs.size, 0)
})

test("unrelated Family lease callbacks cannot prolong cached coordinates or accept retired reads", async () => {
  let time = 1000,
    next = 0
  const jobs = new Map()
  const f = fixture({
    consentLeaseMs: 100,
    now: () => time,
    timers: {
      setTimeout(fn, delay) {
        jobs.set(++next, { fn, delay })
        return next
      },
      clearTimeout(id) {
        jobs.delete(id)
      },
    },
  })
  try {
    await f.owner.mount()
    for (const fn of f.events.get("click:family-circles"))
      fn({ features: [{ properties: { id: 7 } }], lngLat: [13, 52] })
    for (const elapsed of [20, 40, 80]) {
      time = 1000 + elapsed
      f.owner.lease({ milliseconds: 30000 })
      assert.ok([...jobs.values()].some((job) => job.delay === 100 - elapsed))
    }
    const late = defer()
    f.reader.read = () => late.promise
    const pending = f.owner.reconnect()
    await Promise.resolve()
    time = 1100
    const expiry = [...jobs.values()].find((job) => job.delay === 20)
    expiry.fn()
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    assert.equal(f.sources.get("family-history").data.features.length, 0)
    assert.equal(f.popups[0].removed, true)
    f.reader.read = async (resource) => ({
      data:
        resource === "family_locations" ? { locations: [] } : { members: [] },
    })
    await f.owner.reconnect()
    late.resolve({
      data: {
        locations: [{ user_id: 7, latitude: 52, longitude: 13 }],
        members: [],
      },
    })
    await pending
    assert.equal(f.sources.get("family-members").data.features.length, 0)
  } finally {
    f.owner.destroy()
  }
  assert.equal(jobs.size, 0)
})

test("family geometry becomes ready after style load while basemap tiles remain pending", async () => {
  const f = fixture({ loaded: false })
  const mounting = f.owner.mount()
  try {
    await new Promise((resolve) => setImmediate(resolve))
    for (const ready of [...(f.events.get("style.load") ?? [])]) ready()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.reads.length, 2)
    assert.equal(await mounting, "ready")
    assert.equal(f.sources.get("family-members").data.features.length, 1)
    f.releaseLoad()
    assert.equal(f.reads.length, 2)
  } finally {
    f.owner.destroy()
    await mounting
  }
})

test("family empty guidance display follows consent despite flex styling", async () => {
  const f = fixture()
  try {
    await f.owner.mount()
    assert.equal(f.empty.style.display, "none")
    f.owner.clear()
    assert.equal(f.empty.style.display, "")
    await f.owner.reconnect()
    assert.equal(f.empty.style.display, "none")
  } finally {
    f.owner.destroy()
  }
})


test("native Family offline blocks queued refreshes until fresh admission online", async () => {
  let offline = false
  const f = fixture({ isOffline: () => offline })
  try {
    await f.owner.mount()
    assert.equal(f.sources.get("family-members").data.features.length, 1)
    offline = true
    f.owner.clear()
    const reads = f.reads.length
    await f.owner.reconnect()
    assert.equal(f.reads.length, reads)
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    offline = false
    await f.owner.reconnect()
    assert.equal(f.reads.length, reads + 2)
    assert.equal(f.sources.get("family-members").data.features.length, 1)
  } finally {
    f.owner.destroy()
  }
})


test("native Family offline owns erasure refresh and window listener teardown lazily", async () => {
  const window = new EventTarget()
  const f = fixture({ window })
  try {
    await f.owner.mount()
    assert.equal(f.sources.get("family-members").data.features.length, 1)
    window.dispatchEvent(new Event("offline"))
    assert.equal(f.sources.get("family-members").data.features.length, 0)
    const reads = f.reads.length
    await f.owner.reconnect()
    assert.equal(f.reads.length, reads)
    window.dispatchEvent(new Event("online"))
    await new Promise(resolve => setImmediate(resolve))
    assert.equal(f.sources.get("family-members").data.features.length, 1)
    assert.equal(f.reads.length, reads + 2)
  } finally {
    f.owner.destroy()
  }
  const reads = f.reads.length
  window.dispatchEvent(new Event("online"))
  window.dispatchEvent(new Event("offline"))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(f.reads.length, reads)
})
