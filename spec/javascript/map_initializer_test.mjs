import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const basemapUrlSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/basemap_url.js",
    import.meta.url,
  ),
  "utf8",
)

async function loadMapInitializer({ getMapStyle, Toast }) {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/map_initializer.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
  const dependencies = `
    const maplibregl = globalThis.__mapInitializerMaplibre
    const getMapStyle = globalThis.__mapInitializerGetMapStyle
    const Toast = globalThis.__mapInitializerToast
    const translate = (key) => key
    ${basemapUrlSource.replace(/^export /gm, "")}
  `
  globalThis.__mapInitializerGetMapStyle = getMapStyle
  globalThis.__mapInitializerToast = Toast
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`
  return await import(`${url}#${Date.now()}`)
}

class FakeMap {
  constructor(options) {
    this.options = options
    this.listeners = { "style.load": [], error: [], load: [] }
    this.setStyles = []
  }

  on(event, callback) {
    this.listeners[event].push(callback)
  }

  once(event, callback) {
    const wrapped = (payload) => {
      this.off(event, wrapped)
      callback(payload)
    }
    this.on(event, wrapped)
  }

  off(event, callback) {
    this.listeners[event] = this.listeners[event].filter((c) => c !== callback)
  }

  emit(event, payload) {
    for (const callback of [...this.listeners[event]]) callback(payload)
  }

  setStyle(style, options) {
    this.setStyles.push({ style, options })
  }

  addControl() {}
}

const STYLE_URL = "https://tiles.example/style.json"

async function initializeWithCustomStyle({ emitOnConstruct } = {}) {
  const state = { map: null, errors: [] }
  globalThis.__mapInitializerMaplibre = {
    Map: class extends FakeMap {
      constructor(options) {
        super(options)
        state.map = this
        if (emitOnConstruct) queueMicrotask(() => emitOnConstruct(this))
      }
    },
    NavigationControl: class {},
    AttributionControl: class {},
  }
  state.fallback = { version: 8, sources: {}, layers: [] }
  const { MapInitializer } = await loadMapInitializer({
    getMapStyle: async (_styleName, options) =>
      options.vectorTilesUrl ? STYLE_URL : state.fallback,
    Toast: { error: (message) => state.errors.push(message) },
  })

  await MapInitializer.initialize({}, { vectorTilesUrl: STYLE_URL })
  await new Promise((resolve) => setImmediate(resolve))
  return state
}

test("falls back from an unavailable initial custom style URL", async () => {
  const state = await initializeWithCustomStyle({
    emitOnConstruct: (map) =>
      map.emit("error", { error: { url: STYLE_URL, status: 404 } }),
  })

  assert.deepEqual(state.map.setStyles, [
    { style: state.fallback, options: { diff: false } },
  ])
  assert.equal(state.errors.length, 1)
})

test("keeps a custom style whose tiles fail to load", async () => {
  const state = await initializeWithCustomStyle({
    emitOnConstruct: (map) =>
      map.emit("error", { error: { url: "https://tiles.example/3/4/5.pbf" } }),
  })

  assert.deepEqual(state.map.setStyles, [])
  assert.deepEqual(state.errors, [])
})

test("stops watching for style errors once the custom style loads", async () => {
  const state = await initializeWithCustomStyle({
    emitOnConstruct: (map) => map.emit("style.load"),
  })
  state.map.emit("error", { error: { url: STYLE_URL } })

  assert.deepEqual(state.map.setStyles, [])
  assert.deepEqual(state.errors, [])
})
