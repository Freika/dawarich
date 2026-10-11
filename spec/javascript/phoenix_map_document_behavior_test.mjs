import assert from "node:assert/strict"
import { test } from "node:test"
import { mountHost } from "../../app-phoenix/assets/js/map/runtime/host.js"

function fixture() {
  const calls = { controls: [], fits: [], removed: 0, bounds: [] }
  const loading = { hidden: false }
  let response = {
    status: "ok",
    data: {
      min_lng: 12,
      min_lat: 51,
      max_lng: 13,
      max_lat: 52,
      point_count: 4,
    },
  }
  const range = {
    startAt: "2026-03-01T00:00+01:00",
    endAt: "2026-03-02T00:00+01:00",
    timezone: "Europe/Berlin",
  }
  const element = {
    dataset: { mapConfig: JSON.stringify({ revision: 1, range }) },
    querySelector: () => loading,
    appendChild() {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
  }
  const owner = mountHost({
    element,
    pushEvent() {},
    attach() {},
    reader: {
      reset() {},
      destroy() {},
      async read(resource, params, opts) {
        calls.bounds.push({ resource, params, opts })
        return await response
      },
    },
    loadStyle: async () => ({}),
    loadLibrary: async () => ({
      NavigationControl: class {},
      Map: class {
        constructor(options) {
          calls.options = options
        }
        getContainer() {
          return { getBoundingClientRect: () => ({ left: 200, right: 1280 }) }
        }
        addControl(control, position) {
          calls.controls.push({ control, position })
        }
        fitBounds(bounds, options) {
          calls.fits.push({ bounds, options })
        }
        remove() {
          calls.removed++
        }
      },
    }),
  })
  return {
    owner,
    calls,
    element,
    loading,
    range,
    respond: (next) => {
      response = next
    },
  }
}

test("native map document owns navigation controls across reconnect and removes one map", async () => {
  const f = fixture()
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.equal(f.calls.controls.length, 1)
    assert.equal(f.calls.controls[0].position, "top-right")
    assert.deepEqual(f.calls.options.center, [0, 0])
    assert.equal(f.calls.options.zoom, 2)
    await f.owner.reconnect()
    assert.equal(f.calls.controls.length, 1)
  } finally {
    f.owner.destroy()
  }
  assert.equal(f.calls.removed, 1)
})

test("native document fits the admitted range once and preserves empty-range viewport", async () => {
  const f = fixture()
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.deepEqual(f.calls.fits[0].bounds, [
      [12, 51],
      [13, 52],
    ])
    assert.equal(f.calls.fits[0].options.maxZoom, 15)
    assert.equal(f.calls.bounds[0].resource, "bounds")
    assert.equal(f.calls.bounds[0].params.start_at, f.range.startAt)
    assert.equal(f.calls.bounds[0].params.end_at, f.range.endAt)
    await f.owner.update({
      ...f.owner.config,
      revision: 2,
      pointsEnabled: true,
    })
    assert.equal(f.calls.fits.length, 1)
    f.respond({ status: "no_data", data: { point_count: 0 } })
    await f.owner.update({
      ...f.owner.config,
      revision: 3,
      range: { ...f.range, startAt: "2020-01-01" },
    })
    assert.equal(f.calls.fits.length, 1)
    assert.equal(f.element.dataset.mapState, "ready")
  } finally {
    f.owner.destroy()
  }
})

test("native document publishes loading until current bounds settle and discards obsolete replies", async () => {
  const f = fixture()
  let resolve
  f.respond(
    new Promise((done) => {
      resolve = done
    }),
  )
  const mounting = f.owner.mount()
  try {
    for (let n = 0; n < 12; n++) await Promise.resolve()
    assert.equal(f.calls.bounds.length, 1)
    assert.equal(f.element.dataset.mapState, "loading")
    assert.equal(f.loading.hidden, false)
    f.respond({
      status: "ok",
      data: {
        min_lng: 21,
        min_lat: 61,
        max_lng: 22,
        max_lat: 62,
        point_count: 2,
      },
    })
    assert.equal(
      await f.owner.update({
        ...f.owner.config,
        revision: 2,
        range: { ...f.range, startAt: "2026-04-01" },
      }),
      "ready",
    )
    resolve({
      status: "ok",
      data: { min_lng: 1, min_lat: 1, max_lng: 2, max_lat: 2, point_count: 2 },
    })
    await mounting
    await new Promise((done) => setImmediate(done))
    assert.deepEqual(
      f.calls.fits.map((fit) => fit.bounds),
      [
        [
          [21, 61],
          [22, 62],
        ],
      ],
    )
    assert.equal(f.loading.hidden, true)
    assert.equal(f.element.dataset.mapState, "ready")
  } finally {
    resolve({ status: "no_data", data: {} })
    await mounting
    f.owner.destroy()
  }
})

test("failed optional bounds read keeps the native map usable and retries next refresh", async () => {
  const f = fixture()
  f.respond(Promise.reject(new Error("Synthetic bounds refusal")))
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.equal(f.calls.removed, 0)
    f.respond({
      status: "ok",
      data: {
        min_lng: 12,
        min_lat: 51,
        max_lng: 13,
        max_lat: 52,
        point_count: 2,
      },
    })
    assert.equal(await f.owner.reconnect(), "ready")
    assert.equal(f.calls.fits.length, 1)
  } finally {
    f.owner.destroy()
  }
})

test("native bounds fit keeps the current left panel clear", async () => {
  const f = fixture()
  f.element.closest = () => ({
    querySelector: () => ({
      getBoundingClientRect: () => ({ left: 210, right: 560 }),
    }),
  })
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.deepEqual(f.calls.fits[0].options.padding, {
      top: 50,
      right: 50,
      bottom: 50,
      left: 372,
    })
  } finally {
    f.owner.destroy()
  }
})
