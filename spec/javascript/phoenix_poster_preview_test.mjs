import assert from "node:assert/strict"
import { test } from "node:test"
import { createBackdrop } from "../../app-phoenix/assets/js/poster/backdrop.js"
import { createPosterLifecycle } from "../../app-phoenix/assets/js/poster/lifecycle.js"
import {
  collectCoords,
  fitFrame,
  trackBounds,
} from "../../app-phoenix/assets/js/poster/preview.js"
import { createRestyle } from "../../app-phoenix/assets/js/poster/style.js"

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

const tokens = {
  bg: "#101010",
  text: "#fafafa",
  water: "#0000ff",
  parks: "#00ff00",
  road_motorway: "#111111",
  road_primary: "#222222",
  road_secondary: "#333333",
  road_tertiary: "#444444",
  road_residential: "#555555",
  road_default: "#666666",
}
const route = {
  type: "Feature",
  geometry: {
    type: "LineString",
    coordinates: [
      [13.4, 52.5],
      [13.5, 52.6],
    ],
  },
}

function classList() {
  const names = new Set(["opacity-0"])
  return {
    add: (name) => names.add(name),
    remove: (name) => names.delete(name),
    contains: (name) => names.has(name),
  }
}

function fakeLibrary() {
  const live = new Set()
  let created = 0
  class FakeMap {
    constructor(options) {
      created++
      this.options = options
      this.handlers = {}
      this.blobRequests = []
      this.touchZoomRotate = {
        disableRotation: () => {
          this.touchRotation = false
        },
      }
      this.keyboard = {
        disableRotation: () => {
          this.keyRotation = false
        },
      }
      live.add(this)
    }
    on(type, handler) {
      this.handlers[type] = [...(this.handlers[type] ?? []), handler]
    }
    once(type, handler) {
      this.on(type, handler)
    }
    fire(type) {
      for (const handler of this.handlers[type] ?? []) handler()
    }
    getCanvas() {
      return {
        toBlob: (callback, type, quality) =>
          this.blobRequests.push({ callback, type, quality }),
      }
    }
    getCenter() {
      return { lat: 52.52, lng: 13.405 }
    }
    resize() {}
    setStyle(style) {
      this.style = style
    }
    remove() {
      live.delete(this)
    }
  }
  return {
    library: { Map: FakeMap },
    live,
    get created() {
      return created
    },
  }
}

function elements() {
  const dialog = new EventTarget()
  dialog.open = false
  dialog.showModal = () => {
    dialog.open = true
  }
  dialog.close = () => {
    dialog.open = false
  }
  return {
    dialog,
    stage: { clientWidth: 1000, clientHeight: 800, children: [] },
    frame: { style: {}, clientWidth: 300, clientHeight: 400, dataset: {} },
    map: {},
    overlay: {
      width: 0,
      height: 0,
      getContext: () => ({
        clearRect() {},
        createLinearGradient: () => ({ addColorStop() {} }),
        fillRect() {},
        fillText() {},
        save() {},
        restore() {},
      }),
    },
    backdrop: {
      classList: classList(),
      removeAttribute(name) {
        delete this[name]
      },
    },
  }
}

function urls() {
  const created = []
  const revoked = []
  return {
    created,
    revoked,
    createObjectURL: () => {
      created.push(`blob:${created.length}`)
      return created.at(-1)
    },
    revokeObjectURL: (url) => revoked.push(url),
  }
}

function environment() {
  return {
    addEventListener() {},
    removeEventListener() {},
    devicePixelRatio: 1,
    getComputedStyle: () => ({
      paddingLeft: "0",
      paddingRight: "0",
      paddingTop: "0",
      paddingBottom: "0",
      marginTop: "0",
      marginBottom: "0",
    }),
  }
}

function lifecycle(overrides = {}) {
  const library = fakeLibrary()
  const dom = elements()
  const studio = createPosterLifecycle({
    elements: dom,
    poster: {
      load: async () => ({
        geojson: { type: "FeatureCollection", features: [route] },
        guardCoords: [[13.4, 52.5]],
        defaultTitle: "",
      }),
      fallbackBounds: () => null,
    },
    loadLibrary: async () => library.library,
    loadThemeTokens: async () => tokens,
    loadFonts: async () => {},
    window: environment(),
    URL: urls(),
    ...overrides,
  })
  return { studio, library, dom }
}

test("close while theme fonts or backdrop resolves creates no preview", async () => {
  for (const stage of ["loadThemeTokens", "loadFonts", "loadLibrary"]) {
    const pending = deferred()
    const library = fakeLibrary()
    const { studio, dom } = lifecycle({
      loadLibrary: async () => library.library,
      [stage]: () => pending.promise,
    })
    const opening = studio.open({ themeKey: "noir" })
    await tick()
    studio.close()
    pending.resolve(stage === "loadLibrary" ? library.library : tokens)
    await opening
    assert.equal(library.created, 0, stage)
    assert.equal(dom.dialog.open, false, stage)
  }

  const url = urls()
  const { studio, library, dom } = lifecycle({ URL: url })
  await studio.open({ themeKey: "noir" })
  const [map] = library.live
  map.fire("idle")
  studio.close()
  map.blobRequests[0].callback(new Blob(["late"]))
  assert.deepEqual(url.created, [])
  assert.equal(dom.backdrop.src, undefined)
  assert.equal(dom.backdrop.classList.contains("opacity-0"), true)
})

test("repeated open-close leaves one map while open and zero while closed", async () => {
  const { studio, library, dom } = lifecycle()
  for (let round = 0; round < 3; round++) {
    await studio.open({ themeKey: "noir" })
    await studio.open({ themeKey: "noir" })
    assert.equal(library.live.size, 1)
    assert.equal(dom.dialog.open, true)
    studio.close()
    studio.close()
    assert.equal(library.live.size, 0)
  }
  assert.equal(library.created, 3)
})

test("backdrop replacement revokes old URL", () => {
  const url = urls()
  const image = elements().backdrop
  const backdrop = createBackdrop(image, { URL: url })
  const callbacks = []
  const canvas = {
    toBlob: (callback, type, quality) =>
      callbacks.push([callback, type, quality]),
  }
  backdrop.update(canvas)
  backdrop.update(canvas)
  assert.deepEqual(
    callbacks.map((entry) => entry.slice(1)),
    [
      ["image/jpeg", 0.5],
      ["image/jpeg", 0.5],
    ],
  )
  callbacks[0][0](new Blob(["a"]))
  callbacks[1][0](new Blob(["b"]))
  assert.equal(image.src, "blob:1")
  assert.deepEqual(url.revoked, ["blob:0"])
  assert.equal(image.classList.contains("opacity-0"), false)
  backdrop.release()
  assert.deepEqual(url.revoked, ["blob:0", "blob:1"])
  assert.equal(image.src, undefined)
})

test("preview maps disable rotation, frame the outlier-trimmed track and restyle after a debounce", async () => {
  const trimmed = []
  const { studio, library } = lifecycle({
    trim: (coords) => {
      trimmed.push(coords.length)
      return coords
    },
  })
  await studio.open({ themeKey: "noir" })
  const [map] = library.live
  assert.equal(map.touchRotation, false)
  assert.equal(map.keyRotation, false)
  assert.equal(map.options.dragRotate, false)
  assert.equal(map.options.preserveDrawingBuffer, true)
  assert.deepEqual(map.options.bounds, [
    [13.4, 52.5],
    [13.5, 52.6],
  ])
  assert.deepEqual(trimmed, [2])
  assert.equal(map.options.style.layers.at(-1).id, "poster_track")

  const timers = []
  const restyle = createRestyle({
    timers: {
      setTimeout: (callback, delay) => {
        timers.push({ callback, delay, cleared: false })
        return timers.length - 1
      },
      clearTimeout: (id) => {
        if (timers[id]) timers[id].cleared = true
      },
    },
    apply: () => timers.push("applied"),
  })
  restyle.schedule()
  restyle.schedule()
  assert.deepEqual(
    timers.map((timer) => [timer.delay, timer.cleared]),
    [
      [150, true],
      [150, false],
    ],
  )
  timers[1].callback()
  restyle.cancel()
  assert.equal(timers.at(-1), "applied")
})

test("bounds fall back to the live map view and pad a single point", () => {
  assert.equal(trackBounds({ features: [] }), null)
  assert.deepEqual(
    trackBounds({
      features: [{ geometry: { type: "Point", coordinates: [10, 20] } }],
    }),
    [
      [9.99, 19.99],
      [10.01, 20.01],
    ],
  )
  assert.deepEqual(
    collectCoords({
      features: [
        {
          geometry: {
            type: "MultiLineString",
            coordinates: [[[1, 2]], [[3, 4]]],
          },
        },
        { geometry: null },
      ],
    }),
    [
      [1, 2],
      [3, 4],
    ],
  )
})

test("the frame keeps its aspect inside the stage after reserving sibling controls", () => {
  const style = (values = {}) => ({
    paddingLeft: "10",
    paddingRight: "10",
    paddingTop: "20",
    paddingBottom: "20",
    marginTop: "8",
    marginBottom: "0",
    ...values,
  })
  const stage = {
    clientWidth: 1020,
    clientHeight: 840,
    children: [
      { dataset: { posterFrame: "" }, offsetHeight: 999 },
      { dataset: { posterBackdrop: "" }, offsetHeight: 999 },
      { dataset: {}, offsetHeight: 32 },
    ],
  }
  const size = fitFrame(stage, 0.75, { getComputedStyle: () => style() })
  assert.deepEqual(size, { width: 547, height: 730 })
  assert.ok(Math.abs(size.width / size.height - 0.75) < 0.01)
})

function fakeRoot(dom, swatches) {
  const lookup = {
    dialog: dom.dialog,
    stage: dom.stage,
    frame: dom.frame,
    map: dom.map,
    overlay: dom.overlay,
    backdrop: dom.backdrop,
    status: { textContent: "" },
    "theme-label": { textContent: "" },
    recenter: new EventTarget(),
  }
  return {
    dataset: {
      posterConfig: JSON.stringify({
        fonts: {},
        strings: { open_failed: "Poster studio failed to open: %{error}" },
      }),
    },
    lookup,
    querySelector: (selector) =>
      lookup[/data-poster-([a-z-]+)/.exec(selector)[1]],
    querySelectorAll: (selector) =>
      selector === "[data-poster-swatch]" ? swatches : [],
  }
}

function swatch(key, name) {
  const element = new EventTarget()
  element.dataset = { key, name }
  element.classList = {
    toggle: (_name, on) => {
      element.ring = on
    },
  }
  element.setAttribute = (attribute, value) => {
    element[attribute] = value
  }
  return element
}

test("closing the native dialog disposes the preview and open failures stay visible in the studio", async () => {
  const { mountPosterStudio } = await import(
    "../../app-phoenix/assets/js/poster/runtime.js"
  )
  const library = fakeLibrary()
  const dom = elements()
  const swatches = [swatch("noir", "Noir"), swatch("ocean", "Ocean")]
  const root = fakeRoot(dom, swatches)
  const themes = []
  globalThis.fetch = async (url) => {
    themes.push(url)
    return { ok: true, json: async () => tokens }
  }
  const owner = mountPosterStudio({
    root,
    source: {
      snapshot: async () => ({
        revision: 1,
        range: {},
        points: [],
        geojson: { type: "FeatureCollection", features: [route] },
      }),
    },
    loadLibrary: async () => library.library,
    window: environment(),
  })
  await owner.open()
  assert.deepEqual(themes, ["/poster_themes/noir.json"])
  assert.equal(library.live.size, 1)
  assert.equal(swatches[0]["aria-pressed"], "true")
  assert.equal(root.lookup["theme-label"].textContent, "Noir")
  dom.dialog.close()
  dom.dialog.dispatchEvent(new Event("close"))
  assert.equal(library.live.size, 0)

  const failing = mountPosterStudio({
    root,
    source: {
      snapshot: async () => {
        throw new Error("synthetic read failure")
      },
    },
    loadLibrary: async () => library.library,
    window: environment(),
  })
  await failing.open()
  assert.equal(dom.dialog.open, true)
  assert.equal(
    root.lookup.status.textContent,
    "Poster studio failed to open: synthetic read failure",
  )
  assert.equal(library.live.size, 0)
  owner.destroy()
  failing.destroy()
  delete globalThis.fetch
})
