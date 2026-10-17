import assert from "node:assert/strict"
import { test } from "node:test"
import { createSelectionQuery } from "../../app-phoenix/assets/js/map/selection/query.js"
import { createAreaSelection } from "../../app-phoenix/assets/js/map/selection/state.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

const bounds = { minLng: 13.3, maxLng: 13.5, minLat: 52.4, maxLat: 52.6 }
const range = {
  startAt: "2026-03-29T00:00:00+01:00",
  endAt: "2026-03-29T23:59:00+02:00",
  importId: "7",
}

test("selection requests include anomalies and current import window", async () => {
  const calls = []
  const reader = {
    pages: (resource, params, options) => {
      calls.push({ resource, params, options })
      return Promise.resolve([{ id: 1, anomaly: true }])
    },
    read: (resource, params, options) => {
      calls.push({ resource, params, options })
      return Promise.resolve({ status: "ok", data: [{ id: 9 }] })
    },
  }
  const query = createSelectionQuery({ reader })
  const signal = new AbortController().signal
  const result = await query.select(bounds, range, { signal })
  assert.deepEqual(result, {
    points: [{ id: 1, anomaly: true }],
    visits: [{ id: 9 }],
  })
  assert.deepEqual(calls[0], {
    resource: "points",
    params: {
      start_at: range.startAt,
      end_at: range.endAt,
      min_longitude: "13.3",
      max_longitude: "13.5",
      min_latitude: "52.4",
      max_latitude: "52.6",
      include_anomalies: "true",
      import_id: "7",
    },
    options: { signal, maxRows: 10000 },
  })
  assert.deepEqual(calls[1].params, {
    start_at: range.startAt,
    end_at: range.endAt,
    selection: "true",
    sw_lat: "52.4",
    sw_lng: "13.3",
    ne_lat: "52.6",
    ne_lng: "13.5",
  })
})

function mapMock() {
  const state = { dragPan: true, boxZoom: true, cursor: "" }
  const handlers = new Map()
  return {
    state,
    handlers,
    dragPan: {
      enable: () => {
        state.dragPan = true
      },
      disable: () => {
        state.dragPan = false
      },
    },
    boxZoom: {
      enable: () => {
        state.boxZoom = true
      },
      disable: () => {
        state.boxZoom = false
      },
    },
    getCanvas: () => ({ style: state }),
    on: (type, fn) => handlers.set(type, fn),
    off: (type, fn) => handlers.get(type) === fn && handlers.delete(type),
    unproject: ([x, y]) => ({ lng: 13 + x / 100, lat: 52 + y / 100 }),
  }
}

function fixture() {
  const map = mapMock()
  const pending = []
  const pushed = []
  const selection = createAreaSelection({
    map,
    query: {
      select: (b, _r, { signal }) => {
        const request = deferred()
        pending.push({ bounds: b, signal, request })
        return request.promise
      },
    },
    getRange: () => range,
    pushEvent: (event, payload, reply) =>
      pushed.push({ event, payload, reply }),
  })
  return { map, pending, pushed, selection }
}

function drag(map, from, to) {
  map.handlers.get("mousedown")({
    point: { x: from[0], y: from[1] },
    preventDefault() {},
  })
  map.handlers.get("mousemove")({ point: { x: to[0], y: to[1] } })
  map.handlers.get("mouseup")({ point: { x: to[0], y: to[1] } })
}

test("cancel restores map gestures and prevents a late selection result", async () => {
  const { map, pending, selection } = fixture()
  selection.start()
  assert.equal(map.state.dragPan, false)
  selection.cancel()
  assert.equal(map.state.dragPan, true)
  assert.equal(map.state.boxZoom, true)
  assert.equal(map.handlers.size, 0)
  selection.start()
  assert.equal(map.state.dragPan, false)
  assert.equal(map.state.boxZoom, false)
  drag(map, [10, 10], [30, 40])
  assert.deepEqual(pending[0].bounds, {
    minLng: 13.1,
    maxLng: 13.3,
    minLat: 52.1,
    maxLat: 52.4,
  })
  selection.cancel()
  assert.equal(pending[0].signal.aborted, true)
  assert.equal(map.state.dragPan, true)
  assert.equal(map.state.boxZoom, true)
  assert.equal(map.handlers.size, 0)
  pending[0].request.resolve({ points: [{ id: 1 }], visits: [] })
  await Promise.resolve()
  assert.equal(selection.state.points.length, 0)
})

test("bulk failure leaves selection and data intact", async () => {
  const { map, pending, pushed, selection } = fixture()
  selection.start()
  drag(map, [10, 10], [30, 40])
  pending[0].request.resolve({
    points: [{ id: 1 }, { id: 2 }],
    visits: [{ id: 5 }],
  })
  await selection.ready
  assert.equal(selection.state.points.length, 2)

  const failed = selection.deletePoints()
  assert.deepEqual(pushed[0].payload, { point_ids: [1, 2] })
  pushed[0].reply({ error: "forbidden" })
  assert.deepEqual(await failed, { status: "error", error: "forbidden" })
  assert.deepEqual(
    selection.state.points.map((point) => point.id),
    [1, 2],
  )

  const done = selection.deletePoints()
  pushed[1].reply({ ok: true, count: 2 })
  assert.deepEqual(await done, { status: "deleted", count: 2 })
  assert.equal(selection.state.points.length, 0)
  assert.equal(selection.state.visits.length, 1)
})
