import assert from "node:assert/strict"
import test from "node:test"
import { renderRouteVideo } from "../../app-phoenix/assets/js/video/render/engine.js"
import { styleForVideo } from "../../app-phoenix/assets/js/video/render/map_capture.js"
import { createRenderRuns } from "../../app-phoenix/assets/js/video/render/operation.js"

const TRACK = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      properties: {},
      geometry: {
        type: "LineString",
        coordinates: [
          [12.3712, 51.3402],
          [12.376, 51.3402],
          [12.38, 51.341],
        ],
      },
    },
  ],
}
const STYLE = {
  version: 8,
  sources: { "poster-track": { type: "geojson", data: TRACK } },
  layers: [
    { id: "poster_track_casing", paint: { "line-opacity": 0.8 } },
    {
      id: "poster_track",
      source: "poster-track",
      paint: { "line-opacity": 1 },
    },
  ],
}
const kit = {
  TRACK_SOURCE_ID: "poster-track",
  trackBounds: () => [
    [12.37, 51.34],
    [12.38, 51.342],
  ],
}

function context2d() {
  const target = {
    measureText: (value) => ({ width: String(value).length * 6 }),
    createLinearGradient: () => ({ addColorStop() {} }),
  }
  return new Proxy(target, {
    get: (object, key) => (key in object ? object[key] : () => {}),
    set: (object, key, value) => {
      object[key] = value
      return true
    },
  })
}

function environment({
  autoIdle = true,
  failConstruct = false,
  noContext = false,
} = {}) {
  const maps = []
  const containers = []
  const canvases = []
  let created
  const constructed = new Promise((resolve) => {
    created = resolve
  })
  class FakeMap {
    constructor(options) {
      if (failConstruct) throw new Error("WebGL unavailable")
      this.options = options
      this.handlers = { idle: new Set(), error: new Set() }
      this.removed = false
      this.data = {}
      maps.push(this)
      created(this)
      if (autoIdle) queueMicrotask(() => this.emit("idle"))
    }
    on(type, handler) {
      this.handlers[type]?.add(handler)
    }
    off(type, handler) {
      this.handlers[type]?.delete(handler)
    }
    emit(type, event) {
      for (const handler of [...this.handlers[type]]) handler(event)
    }
    triggerRepaint() {
      if (autoIdle) queueMicrotask(() => this.emit("idle"))
    }
    getSource(id) {
      return {
        setData: (data) => {
          this.data[id] = data
        },
      }
    }
    jumpTo() {}
    getCenter() {
      return { lng: 12.375, lat: 51.34 }
    }
    getZoom() {
      return 14
    }
    cameraForBounds() {
      return { center: { lng: 12.375, lat: 51.341 }, zoom: 14 }
    }
    getCanvas() {
      return { clientWidth: 4, clientHeight: 4 }
    }
    project([x, y]) {
      return { x, y }
    }
    remove() {
      this.removed = true
    }
  }
  const document = {
    body: { appendChild: (element) => containers.push(element) },
    createElement(tag) {
      if (tag === "canvas") {
        const canvas = {
          width: 0,
          height: 0,
          getContext: () => (noContext ? null : context2d()),
        }
        canvases.push(canvas)
        return canvas
      }
      return {
        style: {},
        removed: false,
        remove() {
          this.removed = true
        },
      }
    },
  }
  const encoder = {
    frames: [],
    aborted: false,
    finalized: false,
    async addFrame(_canvas, index) {
      this.frames.push(index)
    },
    async finalize() {
      this.finalized = true
      return new Blob(["mp4"], { type: "video/mp4" })
    },
    abort() {
      this.aborted = true
    },
  }
  const timers = {
    pending: new Set(),
    setTimeout(callback, ms) {
      const timer = { callback, ms }
      this.pending.add(timer)
      return timer
    },
    clearTimeout(timer) {
      this.pending.delete(timer)
    },
  }
  let libraryLoads = 0
  return {
    maps,
    containers,
    canvases,
    encoder,
    timers,
    constructed,
    get libraryLoads() {
      return libraryLoads
    },
    deps: {
      kit,
      document,
      timers,
      createEncoder: async () => encoder,
      ensureFonts: async () => ({ mono: "Mono", sans: "Sans" }),
      loadLibrary: async () => {
        libraryLoads += 1
        return { Map: FakeMap }
      },
    },
  }
}

const options = (overrides = {}) => ({
  style: STYLE,
  trackGeojson: TRACK,
  points: [],
  stats: { distanceM: 1000 },
  width: 8,
  height: 8,
  fps: 4,
  durationSec: 1,
  labels: {
    day: "DAY",
    distance: "DISTANCE",
    ofTotal: "OF TOTAL",
    tagline: "TAG",
    travelledOver: (days) => `${days}`,
  },
  ...overrides,
})

test("a full render encodes every planned frame and returns the MP4", async () => {
  const env = environment()
  const progress = []
  const result = await renderRouteVideo(
    options({ onProgress: (done, total) => progress.push([done, total]) }),
    env.deps,
  )
  assert.equal(result.blob.type, "video/mp4")
  assert.deepEqual(env.encoder.frames, [0, 1, 2, 3])
  assert.deepEqual(progress.at(-1), [4, 4])
  assert.equal(env.encoder.finalized, true)
  assert.equal(env.encoder.aborted, false)
  assert.equal(env.maps[0].removed, true)
  assert.equal(env.containers[0].removed, true)
  assert.equal(env.maps[0].options.pixelRatio, 2)
  assert.equal(env.timers.pending.size, 0)
})

test("cancel before first idle releases map encoder and canvas", async () => {
  const env = environment({ autoIdle: false })
  const controller = new AbortController()
  const rendering = renderRouteVideo(
    options({ signal: controller.signal }),
    env.deps,
  )
  const map = await env.constructed
  await Promise.resolve()
  controller.abort()
  await assert.rejects(rendering, { name: "AbortError" })
  assert.equal(map.removed, true)
  assert.equal(env.containers[0].removed, true)
  assert.equal(env.encoder.aborted, true)
  assert.equal(map.handlers.idle.size, 0)
  assert.equal(map.handlers.error.size, 0)
  assert.equal(env.timers.pending.size, 0)
  assert.ok(env.canvases.every((canvas) => canvas.width === 0))
})

test("a first idle that never arrives fails within its bound and releases", async () => {
  const env = environment({ autoIdle: false })
  const rendering = renderRouteVideo(options(), env.deps)
  const map = await env.constructed
  await Promise.resolve()
  const [timer] = [...env.timers.pending]
  timer.callback()
  await assert.rejects(rendering, /Map failed to load/)
  assert.equal(map.removed, true)
  assert.equal(env.encoder.aborted, true)
})

test("map or 2d context failure after encoder setup releases encoder", async () => {
  const broken = environment({ failConstruct: true })
  await assert.rejects(renderRouteVideo(options(), broken.deps), /WebGL/)
  assert.equal(broken.encoder.aborted, true)
  assert.equal(broken.containers[0].removed, true)

  const noContext = environment({ noContext: true })
  await assert.rejects(renderRouteVideo(options(), noContext.deps))
  assert.equal(noContext.encoder.aborted, true)
  assert.equal(noContext.maps[0].removed, true)
  assert.equal(noContext.containers[0].removed, true)
  assert.ok(noContext.canvases.every((canvas) => canvas.width === 0))
})

test("unsupported codec refuses without map allocation", async () => {
  const env = environment()
  env.deps.createEncoder = async () => null
  await assert.rejects(renderRouteVideo(options(), env.deps), {
    code: "unsupported_browser",
  })
  assert.equal(env.maps.length, 0)
  assert.equal(env.libraryLoads, 0)
  assert.equal(env.containers.length, 0)
})

test("old render result cannot replace newer result", async () => {
  const runs = createRenderRuns()
  const applied = []
  let finishFirst
  const first = runs.perform(
    () =>
      new Promise((resolve) => {
        finishFirst = resolve
      }),
    (result) => applied.push(result),
  )
  const firstSignal = runs.signal
  const second = runs.perform(
    async () => "newer",
    (result) => applied.push(result),
  )
  assert.equal(firstSignal.aborted, true)
  await second
  finishFirst("older")
  await first
  assert.deepEqual(applied, ["newer"])
  assert.equal(runs.active, false)
})

test("video style dims the drawn route behind a fresh accent window", () => {
  const prepared = styleForVideo(STYLE, {
    trackSourceId: "poster-track",
    accent: "#2563EB",
    dimOpacity: 0.5,
  })
  assert.deepEqual(prepared.sources["poster-track"].data, {
    type: "FeatureCollection",
    features: [],
  })
  assert.equal(prepared.sources["video-fresh"].lineMetrics, true)
  const track = prepared.layers.find((layer) => layer.id === "poster_track")
  const fresh = prepared.layers.find((layer) => layer.id === "video_fresh")
  assert.equal(track.paint["line-opacity"], 0.5)
  assert.equal(fresh.paint["line-opacity"], 1)
  assert.equal(fresh.source, "video-fresh")
  assert.equal(
    prepared.layers.find((layer) => layer.id === "poster_track_casing").paint[
      "line-opacity"
    ],
    0.4,
  )
  assert.equal(STYLE.sources["poster-track"].data, TRACK)
})
