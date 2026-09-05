import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const url = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const strip = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const cleanup = await read("maps_maplibre/utils/cleanup_helper.js")
const { TimelineSegmentHover, segmentCoordinates } = await import(
  url(
    `${cleanup}\n${strip(await read("maps_maplibre/managers/timeline_segment_hover.js"))}`,
  )
)
const { TracksLayer } = await import(
  url(
    `${await read("maps_maplibre/layers/base_layer.js")}\n${strip(await read("maps_maplibre/layers/tracks_layer.js"))}`,
  )
)
globalThis.requestAnimationFrame = () => 1
globalThis.cancelAnimationFrame = () => {}
const full = {
  type: "Feature",
  properties: {
    id: 1,
    color: "blue",
    segments: [
      {
        id: 10,
        coordinates: [
          [1, 1],
          [2, 2],
        ],
        color: "green",
      },
      { id: 11, start_index: 1, end_index: 2, color: "red" },
    ],
  },
  geometry: {
    type: "LineString",
    coordinates: [
      [0, 0],
      [1, 1],
      [2, 2],
      [3, 3],
    ],
  },
}
function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => {
    resolve = yes
    reject = no
  })
  return { promise, resolve, reject }
}
function setup(fetcher = async () => full) {
  const listeners = new Map()
  globalThis.document = {
    addEventListener(name, cb) {
      listeners.set(name, cb)
    },
    removeEventListener(name) {
      listeners.delete(name)
    },
  }
  const source = {
    setData(data) {
      this.data = data
    },
  }
  const map = {
    opacity: 0.6,
    source,
    on() {},
    off() {},
    getSource() {
      return this.source
    },
    getLayer: () => ({}),
    getPaintProperty() {
      return this.opacity
    },
    setPaintProperty(_id, _key, value) {
      this.opacity = value
    },
  }
  const layer = new TracksLayer(map)
  layer.setSelectedTrack(full)
  layer.segmentsActive = true
  map.opacity = 0.6
  const requests = []
  const controller = {
    map,
    layerManager: { getLayer: () => layer },
    api: {
      fetchTrackWithSegments(id, options) {
        requests.push({ id, ...options })
        return fetcher(id, options)
      },
    },
  }
  let enabled = true
  const manager = new TimelineSegmentHover(controller, () => enabled)
  const event = (id = 10, trackId = 1) => ({
    target: { isConnected: true },
    detail: { trackId, segmentId: id },
  })
  return {
    manager,
    layer,
    map,
    requests,
    event,
    listeners,
    disable: () => {
      enabled = false
    },
  }
}

test("hover animates the exact segment and restores the full track, colors and opacity", async () => {
  const h = setup()
  await h.manager.hover(h.event())
  assert.deepEqual(h.map.source.data.features[0].geometry.coordinates, [
    [1, 1],
    [2, 2],
  ])
  assert.equal(h.layer.flowTrackColor, "green")
  assert.equal(h.layer.animationActive, true)
  h.manager.leave()
  assert.equal(h.map.source.data.features[0], full)
  assert.equal(h.layer.segmentsActive, true)
  assert.equal(h.map.opacity, 0.6)
  h.manager.destroy()
})
test("rapid segment changes share one in-flight request and only the latest wins", async () => {
  const d = deferred(),
    h = setup(() => d.promise)
  const first = h.manager.hover(h.event(10))
  const second = h.manager.hover(h.event(11))
  assert.equal(h.requests.length, 1)
  d.resolve(full)
  await Promise.all([first, second])
  assert.equal(h.layer.flowTrackColor, "red")
  assert.deepEqual(h.layer.selectedFeature.geometry.coordinates, [
    [1, 1],
    [2, 2],
  ])
  await h.manager.hover(h.event(10))
  assert.equal(h.requests.length, 1)
  h.manager.destroy()
})
test("leaving before a response keeps the original selection", async () => {
  const d = deferred(),
    h = setup(() => d.promise)
  const pending = h.manager.hover(h.event())
  h.manager.leave()
  d.resolve(full)
  await pending
  assert.equal(h.layer.selectedFeature, full)
  h.manager.destroy()
})
test("a newer map selection wins both before response and after segment hover", async () => {
  const d = deferred(),
    h = setup(() => d.promise)
  const newer = { ...full, properties: { id: 2 } }
  const pending = h.manager.hover(h.event())
  h.layer.setSelectedTrack(newer)
  d.resolve(full)
  await pending
  assert.equal(h.layer.selectedFeature, newer)
  await h.manager.hover(h.event())
  h.layer.setSelectedTrack(newer)
  h.manager.leave()
  assert.equal(h.layer.selectedFeature, newer)
  h.manager.destroy()
})
test("reset aborts requests and invalidates cached data, while destroy removes listeners", async () => {
  const d = deferred(),
    h = setup(() => d.promise)
  const pending = h.manager.hover(h.event())
  h.listeners.get("timeline-feed:date-navigated")()
  assert.equal(h.requests[0].signal.aborted, true)
  d.resolve(full)
  await pending
  assert.equal(h.layer.selectedFeature, full)
  await h.manager.hover(h.event())
  assert.equal(h.requests.length, 2)
  h.manager.destroy()
  assert.equal(h.listeners.size, 0)
})
test("only one track is cached and failed requests can be retried", async () => {
  let fail = true
  const h = setup(async () => {
    if (fail) throw new Error("offline")
    return full
  })
  await h.manager.hover(h.event())
  assert.equal(h.layer.selectedFeature, full)
  fail = false
  await h.manager.hover(h.event())
  await h.manager.hover(h.event(10, 2))
  await h.manager.hover(h.event(10, 1))
  assert.equal(h.requests.length, 4)
  assert.equal(h.requests[1].signal.aborted, true)
  h.manager.destroy()
})
test("tiled main-layer visibility does not block shimmer, but disabling Tracks does", async () => {
  const h = setup()
  h.layer.visible = false
  await h.manager.hover(h.event())
  assert.notEqual(h.layer.selectedFeature, full)
  h.manager.leave()
  h.disable()
  await h.manager.hover(h.event())
  assert.equal(h.layer.selectedFeature, full)
  assert.equal(h.requests.length, 1)
  h.manager.destroy()
})
test("a replaced map source cannot receive a stale segment response or restoration", async () => {
  const d = deferred(),
    h = setup(() => d.promise)
  const pending = h.manager.hover(h.event())
  const replacement = {
    setData(data) {
      this.data = data
    },
  }
  h.map.source = replacement
  d.resolve(full)
  await pending
  assert.equal(replacement.data, undefined)
  h.manager.destroy()
  assert.equal(replacement.data, undefined)
})
test("map-origin segment broadcasts are ignored", () => {
  const h = setup()
  h.listeners.get("dawarich:segment-hover")({
    target: document,
    detail: { trackId: 1, segmentId: 10 },
  })
  assert.equal(h.requests.length, 0)
  h.manager.destroy()
})
test("legacy slicing is inclusive and invalid or unavailable geometry is never invented", () => {
  assert.deepEqual(segmentCoordinates(full, { start_index: 1, end_index: 2 }), [
    [1, 1],
    [2, 2],
  ])
  for (const segment of [
    undefined,
    {},
    { start_index: -1, end_index: 2 },
    { start_index: 0, end_index: 9 },
    { start_index: 0, end_index: 0 },
    { coordinates: [] },
    {
      coordinates: [
        [1, 2],
        [NaN, 2],
      ],
    },
  ]) {
    assert.equal(segmentCoordinates(full, segment), null)
  }
})

test("a segment overlay arriving during hover keeps its current visibility on restoration", async () => {
  const h = setup()
  h.layer.segmentsActive = false
  await h.manager.hover(h.event())
  h.layer.segmentsActive = true
  h.manager.leave()
  assert.equal(h.layer.selectedFeature, full)
  assert.equal(h.layer.segmentsActive, true)
  h.manager.destroy()
})

test("no prior selection stays empty after hovering a segment", async () => {
  const h = setup()
  h.layer.setSelectedTrack(null)
  await h.manager.hover(h.event())
  assert.equal(h.layer.selectedFeature.geometry.coordinates.length, 2)
  h.manager.leave()
  assert.equal(h.layer.selectedFeature, null)
  assert.deepEqual(h.map.source.data.features, [])
  h.manager.destroy()
})
