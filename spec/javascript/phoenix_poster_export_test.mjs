import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"
import { captureBounds } from "../../app-phoenix/assets/js/poster/export/capture.js"
import { createPosterExports } from "../../app-phoenix/assets/js/poster/export/operation.js"
import {
  exportPoster,
  studioFilename,
} from "../../app-phoenix/assets/js/poster/export/render.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

function fakeDocument() {
  const body = new Set()
  return {
    body: { appendChild: (element) => body.add(element), nodes: body },
    createElement: (tag) => {
      const element = {
        tag,
        style: {},
        width: 0,
        height: 0,
        remove: () => body.delete(element),
        getContext: () => ({
          drawImage: (...args) => {
            element.drawn = args
          },
          getImageData: (_x, _y, width, height) => ({
            data: new Uint8ClampedArray(width * height * 4).fill(200),
          }),
        }),
        toBlob(callback, type) {
          callback(
            new Blob([Uint8Array.from([0xff, 0xd8, 0xff, 0xd9])], { type }),
          )
        },
      }
      return element
    },
  }
}

function fakeLibrary({ failConstruct = false } = {}) {
  const maps = []
  class FakeMap {
    constructor(options) {
      if (failConstruct) throw new Error("WebGL unavailable")
      this.options = options
      this.handlers = {}
      this.removed = false
      maps.push(this)
    }
    once(type, handler) {
      this.handlers[type] = handler
    }
    off(type, handler) {
      if (this.handlers[type] === handler) delete this.handlers[type]
    }
    emit(type, event) {
      const handler = this.handlers[type]
      delete this.handlers[type]
      handler?.(event)
    }
    getCanvas() {
      return { id: "gl" }
    }
    remove() {
      this.removed = true
    }
  }
  return { library: { Map: FakeMap }, maps }
}

function countingSignal() {
  const controller = new AbortController()
  const signal = controller.signal
  let listeners = 0
  const add = signal.addEventListener.bind(signal)
  const remove = signal.removeEventListener.bind(signal)
  signal.addEventListener = (...args) => {
    listeners++
    add(...args)
  }
  signal.removeEventListener = (...args) => {
    listeners--
    remove(...args)
  }
  return {
    controller,
    signal,
    get listeners() {
      return listeners
    },
  }
}

function manualTimers() {
  const pending = []
  return {
    pending,
    setTimeout: (callback, delay) => {
      pending.push({ callback, delay, cleared: false })
      return pending.length - 1
    },
    clearTimeout: (id) => {
      if (pending[id]) pending[id].cleared = true
    },
  }
}

const request = (overrides = {}) => ({
  style: { version: 8 },
  bounds: [
    [13.3, 52.4],
    [13.5, 52.6],
  ],
  width: 1200,
  height: 1600,
  cssSize: { width: 300, height: 400 },
  ...overrides,
})

test("cancel before first map idle releases export map and abort listener", async () => {
  const doc = fakeDocument()
  const { library, maps } = fakeLibrary()
  const counted = countingSignal()
  const timers = manualTimers()
  const capture = captureBounds({
    ...request(),
    library,
    signal: counted.signal,
    document: doc,
    timers,
  })
  await tick()
  assert.equal(maps.length, 1)
  assert.equal(maps[0].options.pixelRatio, 4)
  assert.equal(maps[0].options.preserveDrawingBuffer, true)
  assert.equal(doc.body.nodes.size, 1)
  counted.controller.abort()
  await assert.rejects(capture, { name: "AbortError" })
  assert.equal(maps[0].removed, true)
  assert.equal(doc.body.nodes.size, 0)
  assert.equal(counted.listeners, 0)
  assert.deepEqual(Object.keys(maps[0].handlers), [])
  assert.ok(timers.pending.every((timer) => timer.cleared))
})

test("Map constructor failure removes its container", async () => {
  const doc = fakeDocument()
  const { library } = fakeLibrary({ failConstruct: true })
  await assert.rejects(
    captureBounds({
      ...request(),
      library,
      document: doc,
      timers: manualTimers(),
    }),
    /WebGL unavailable/,
  )
  assert.equal(doc.body.nodes.size, 0)
})

test("an already aborted or never idle capture settles and cleans up", async () => {
  const doc = fakeDocument()
  const { library, maps } = fakeLibrary()
  const aborted = new AbortController()
  aborted.abort()
  await assert.rejects(
    captureBounds({
      ...request(),
      library,
      signal: aborted.signal,
      document: doc,
      timers: manualTimers(),
    }),
    { name: "AbortError" },
  )
  assert.equal(maps.length, 0)
  assert.equal(doc.body.nodes.size, 0)

  const timers = manualTimers()
  const stalled = captureBounds({
    ...request(),
    library,
    document: doc,
    timers,
    timeoutMs: 1000,
  })
  await tick()
  assert.deepEqual(
    timers.pending.map((timer) => timer.delay),
    [1000],
  )
  timers.pending[0].callback()
  await assert.rejects(stalled, /timed out/)
  assert.equal(maps[0].removed, true)
  assert.equal(doc.body.nodes.size, 0)

  const failing = captureBounds({
    ...request(),
    library,
    document: doc,
    timers,
  })
  await tick()
  maps[1].emit("error", { error: new Error("style failed") })
  await assert.rejects(failing, /style failed/)
  assert.deepEqual(Object.keys(maps[1].handlers), [])
  assert.equal(maps[1].removed, true)
})

test("an idle capture copies the GL canvas at export resolution", async () => {
  const doc = fakeDocument()
  const { library, maps } = fakeLibrary()
  const capture = captureBounds({
    ...request(),
    library,
    document: doc,
    timers: manualTimers(),
  })
  await tick()
  maps[0].emit("idle")
  const canvas = await capture
  assert.deepEqual([canvas.width, canvas.height], [1200, 1600])
  assert.deepEqual(canvas.drawn, [{ id: "gl" }, 0, 0, 1200, 1600])
  assert.equal(maps[0].removed, true)
  assert.equal(doc.body.nodes.size, 0)
})

const theme = {
  bg: "#101010",
  text: "#fafafa",
  gradientColor: "#101010",
  route: "#ff0000",
  casing: "#101010",
}

function exportCanvas(width, height) {
  const canvas = fakeDocument().createElement("canvas")
  canvas.width = width
  canvas.height = height
  canvas.getContext = () => ({
    createLinearGradient: () => ({ addColorStop() {} }),
    fillRect() {},
    fillText() {},
    save() {},
    restore() {},
    getImageData: (_x, _y, w, h) => ({
      data: new Uint8ClampedArray(w * h * 4),
    }),
  })
  return canvas
}

test("close before encoding completes cannot download", async () => {
  const pending = deferred()
  const downloads = []
  const exports = createPosterExports({
    exportPoster: () => pending.promise,
    download: (...args) => downloads.push(args),
  })
  const running = exports.run({ title: "Berlin", layout: { id: "print-a3" } })
  assert.equal(exports.busy, true)
  assert.equal(
    (await exports.run({ layout: { id: "print-a3" } })).status,
    "busy",
  )
  exports.cancel()
  assert.equal(exports.busy, false)
  pending.resolve({ blob: new Blob(["png"]), extension: "png", geometry: {} })
  assert.equal((await running).status, "cancelled")
  assert.deepEqual(downloads, [])

  const next = await exports.run({
    title: "Berlin",
    layout: { id: "print-a3" },
  })
  assert.equal(next.status, "done")
  assert.equal(downloads.length, 1)
})

test("a finished export downloads once with the studio filename and reports the effective DPI", async () => {
  const downloads = []
  const exports = createPosterExports({
    exportPoster: async ({ signal }) => {
      assert.equal(signal.aborted, false)
      return {
        blob: new Blob(["png"]),
        extension: "png",
        geometry: { steppedDown: true, effectiveDpi: 175 },
      }
    },
    download: (_blob, name) => downloads.push(name),
  })
  const result = await exports.run({
    title: "Berlin Trip!",
    layout: { id: "print-a0" },
  })
  assert.equal(result.status, "done")
  assert.equal(result.geometry.effectiveDpi, 175)
  assert.deepEqual(downloads, ["dawarich-berlin-trip-print-a0.png"])
  assert.equal(
    studioFilename("", { id: "social-story" }, "png"),
    "dawarich-poster-social-story.png",
  )

  const failing = createPosterExports({
    exportPoster: async () => {
      throw new Error("encoder exploded")
    },
    download: () => downloads.push("unexpected"),
  })
  const failed = await failing.run({ title: "", layout: { id: "print-a3" } })
  assert.equal(failed.status, "failed")
  assert.equal(failed.error.message, "encoder exploded")
  assert.equal(downloads.length, 1)
})

test("export resets its canvas after encoding and stops between stages once aborted", async () => {
  const canvas = exportCanvas(4, 2)
  const result = await exportPoster({
    style: {},
    bounds: [],
    layout: { id: "social-x-header", kind: "pixels", width: 4, height: 2 },
    dpi: 300,
    format: "png",
    theme,
    text: { title: "", subtitle: "", coords: "" },
    font: "Poster",
    maxDimensionPx: 8192,
    capture: async () => canvas,
  })
  assert.equal(result.extension, "png")
  assert.deepEqual([canvas.width, canvas.height], [0, 0])

  const controller = new AbortController()
  await assert.rejects(
    exportPoster({
      style: {},
      bounds: [],
      layout: { id: "social-x-header", kind: "pixels", width: 4, height: 2 },
      dpi: 300,
      format: "png",
      theme,
      text: {},
      font: "Poster",
      maxDimensionPx: 8192,
      signal: controller.signal,
      capture: async () => {
        controller.abort()
        return exportCanvas(4, 2)
      },
    }),
    { name: "AbortError" },
  )
})

async function railsCapture() {
  const source = (
    await readFile(
      new URL(
        "../../app/javascript/poster_studio/render/offscreen_map.js",
        import.meta.url,
      ),
      "utf8",
    )
  ).replace(
    'import * as maplibregl from "maplibre-gl"',
    "const maplibregl = { get Map() { return globalThis.__posterOracleLibrary.Map } }",
  )
  return import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )
}

test("Rails oracle: offscreen capture leaks its container when the Map constructor throws", async (t) => {
  const { captureBounds: railsCaptureBounds } = await railsCapture()
  const doc = fakeDocument()
  const saved = globalThis.document
  t.after(() => {
    globalThis.document = saved
    delete globalThis.__posterOracleLibrary
  })
  globalThis.document = doc
  globalThis.__posterOracleLibrary = fakeLibrary({
    failConstruct: true,
  }).library
  await assert.rejects(railsCaptureBounds(request()), /WebGL unavailable/)
  assert.equal(doc.body.nodes.size, 1)
})

test("Rails oracle: an offscreen capture that never reaches idle never settles", async (t) => {
  const { captureBounds: railsCaptureBounds } = await railsCapture()
  const doc = fakeDocument()
  const saved = globalThis.document
  t.after(() => {
    globalThis.document = saved
    delete globalThis.__posterOracleLibrary
  })
  globalThis.document = doc
  const { library, maps } = fakeLibrary()
  globalThis.__posterOracleLibrary = library
  const aborted = new AbortController()
  aborted.abort()
  let settled = "pending"
  railsCaptureBounds({ ...request(), signal: aborted.signal }).then(
    () => {
      settled = "resolved"
    },
    () => {
      settled = "rejected"
    },
  )
  for (let round = 0; round < 5; round++) await tick()
  assert.equal(settled, "pending")
  assert.equal(maps[0].removed, false)
  assert.equal(doc.body.nodes.size, 1)
})

test("Rails oracle: closing the poster studio during a download still saves the file", async (t) => {
  const source = (
    await readFile(
      new URL(
        "../../app/javascript/controllers/poster_studio_editor_controller.js",
        import.meta.url,
      ),
      "utf8",
    )
  ).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const prelude = `
class Controller {}
const translate = (key) => key
const layoutById = (id) => ({ id, kind: "paper" })
const resolveLayoutGeometry = () => ({ width: 10, height: 10, steppedDown: false })
const resolveTheme = () => ({})
const fontByKey = () => ({ family: "Poster" })
const exportPoster = () => globalThis.__posterEditorOracle.export.promise
const downloadBlob = (...args) => globalThis.__posterEditorOracle.downloads.push(args)
const studioFilename = () => "poster.png"
const Flash = { show() {} }
`
  const { default: Editor } = await import(
    `data:text/javascript;base64,${Buffer.from(`${prelude}\n${source}`).toString("base64")}`
  )
  const oracle = { export: deferred(), downloads: [] }
  const saved = globalThis.window
  t.after(() => {
    globalThis.window = saved
    delete globalThis.__posterEditorOracle
  })
  globalThis.__posterEditorOracle = oracle
  globalThis.window = { removeEventListener() {} }
  const editor = new Editor()
  Object.assign(editor, {
    previewMap: {
      getBounds: () => ({
        getWest: () => 0,
        getSouth: () => 0,
        getEast: () => 1,
        getNorth: () => 1,
      }),
      remove() {},
    },
    layoutSelectTarget: { value: "print-a3" },
    dpiTarget: { value: "300" },
    formatTarget: { value: "png" },
    titleInputTarget: { value: "" },
    fontSelectTarget: { value: "oswald" },
    frameTarget: { clientWidth: 300, clientHeight: 400 },
    statusTarget: { textContent: "" },
    downloadButtonTarget: { disabled: false },
    element: { classList: { add() {} } },
    hasBackdropTarget: false,
    posterStyle: () => ({}),
    posterText: () => ({}),
  })
  const download = editor.download()
  await tick()
  editor.close()
  oracle.export.resolve({ blob: new Blob(["png"]), extension: "png" })
  await download
  assert.equal(oracle.downloads.length, 1)
})
