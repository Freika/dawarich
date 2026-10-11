import assert from "node:assert/strict"
import { test } from "node:test"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"
import { createReplay } from "../../app-phoenix/assets/js/map/replay/runtime.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}

const point = (timestamp, lon = 13.4) => ({
  geometry: { coordinates: [lon, 52.5] },
  properties: { timestamp },
})

function fixture() {
  const frames = new Map()
  const cancelled = []
  const sources = new Map()
  const layers = new Set()
  const handlers = new Map()
  const loads = []
  let next = 0
  const map = {
    addSource: (id, source) => sources.set(id, { ...source }),
    getSource: (id) =>
      sources.has(id) && {
        setData: (data) => {
          sources.get(id).data = data
        },
      },
    removeSource: (id) => sources.delete(id),
    addLayer: (layer) => layers.add(layer.id),
    getLayer: (id) => layers.has(id),
    removeLayer: (id) => layers.delete(id),
    on: (type, layer, fn) => handlers.set(`${type}:${layer}`, fn),
    off: (type, layer, fn) =>
      handlers.get(`${type}:${layer}`) === fn &&
      handlers.delete(`${type}:${layer}`),
  }
  const replay = createReplay({
    map,
    timezone: "Europe/Berlin",
    loadDay: (range, { signal }) => {
      const request = deferred()
      loads.push({ range, signal, request })
      return request.promise
    },
    raf: (fn) => {
      next += 1
      frames.set(next, fn)
      return next
    },
    cancelRaf: (id) => {
      cancelled.push(id)
      frames.delete(id)
    },
  })
  const step = () => {
    const [[id, fn]] = [...frames]
    frames.delete(id)
    fn(id * 16)
  }
  return { replay, frames, cancelled, sources, layers, handlers, loads, step }
}

const day = (date) => ({ startAt: `${date}T00:00`, endAt: `${date}T23:59` })

test("closing replay releases rAF and photo/marker listeners", async () => {
  const f = fixture()
  const opened = f.replay.open(day("2026-06-01"))
  f.loads[0].request.resolve([
    point("2026-06-01T08:00:00Z"),
    point("2026-06-01T08:01:00Z", 13.5),
  ])
  await opened
  assert.equal(f.layers.size, 1)
  assert.equal(f.handlers.size, 1)
  f.replay.play()
  f.step()
  assert.equal(f.frames.size, 1)
  f.replay.close()
  assert.equal(f.frames.size, 0)
  assert.equal(f.cancelled.length, 1)
  assert.equal(f.layers.size, 0)
  assert.equal(f.sources.size, 0)
  assert.equal(f.handlers.size, 0)
  f.replay.play()
  assert.equal(f.frames.size, 0)
})

test("reconnect retains one replay clock", async () => {
  const f = fixture()
  const opened = f.replay.open(day("2026-06-01"))
  f.loads[0].request.resolve([point("2026-06-01T08:00:00Z")])
  await opened
  f.replay.play()
  f.replay.play()
  for (let i = 0; i < 3; i++) f.replay.reconnect()
  assert.equal(f.frames.size, 1)
  f.replay.pause()
  f.replay.reconnect()
  assert.equal(f.frames.size, 0)
})

test("date changes drop old replay point load", async () => {
  const f = fixture()
  const first = f.replay.open(day("2026-06-01"))
  const second = f.replay.setDate(day("2026-06-02"))
  assert.equal(f.loads[0].signal.aborted, true)
  f.loads[1].request.resolve([point("2026-06-02T09:00:00Z")])
  await second
  f.loads[0].request.resolve([point("2026-06-01T09:00:00Z")])
  await first
  assert.equal(f.replay.manager.getCurrentDay(), "2026-06-02")
  assert.equal(f.replay.manager.getDayCount(), 1)
  assert.ok(f.replay.manager instanceof ReplayManager)
})
