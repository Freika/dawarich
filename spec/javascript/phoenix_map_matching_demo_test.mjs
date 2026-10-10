import assert from "node:assert/strict"
import test from "node:test"

const { MapMatchingDemo } = await import(
  "../../app-phoenix/assets/js/hooks/map_matching_demo.js"
)
const demo = await import(
  "../../app-phoenix/assets/js/demo/map_matching_demo.js"
)

function fakeMaplibre(log) {
  class FakeMap {
    constructor(options) {
      this.options = options
      this.handlers = {}
      this.paint = {}
      log.maps.push(this)
    }
    addControl() {}
    on(name, fn) {
      this.handlers[name] = fn
    }
    addSource(id) {
      log.sources.push(id)
    }
    addLayer(layer) {
      log.layers.push(layer.id)
    }
    setPaintProperty(layer, property, value) {
      this.paint[`${layer}:${property}`] = value
    }
    fitBounds() {}
    remove() {
      log.removed += 1
    }
  }
  class Bounds {
    extend() {}
  }
  return {
    Map: FakeMap,
    NavigationControl: class {},
    AttributionControl: class {},
    LngLatBounds: Bounds,
  }
}

function button(mode) {
  const listeners = {}
  const attrs = {}
  const classes = new Set()
  return {
    dataset: { mode },
    setAttribute: (k, v) => {
      attrs[k] = v
    },
    getAttribute: (k) => attrs[k],
    classList: { toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)) },
    addEventListener: (n, fn) => {
      listeners[n] = fn
    },
    removeEventListener: (n) => {
      delete listeners[n]
    },
    click() {
      listeners.click?.({ currentTarget: this })
    },
    listeners,
    attrs,
  }
}

function fixture() {
  const log = { maps: [], sources: [], layers: [], removed: 0 }
  const buttons = [button("original"), button("matched")]
  const loading = {
    removed: false,
    remove() {
      this.removed = true
    },
  }
  const mapEl = {}
  const el = {
    querySelector: (selector) =>
      selector === "[data-demo-map]"
        ? mapEl
        : selector === "[data-demo-loading]"
          ? loading
          : null,
    querySelectorAll: (selector) =>
      selector === "button[data-mode]" ? buttons : [],
  }
  const hook = Object.assign(Object.create(MapMatchingDemo), {
    el,
    loader: async () => ({
      maplibre: fakeMaplibre(log),
      demo,
      style: { version: 8, sources: {}, layers: [] },
    }),
  })
  return { hook, log, buttons, loading, mapEl }
}

test("loads the map lazily into the map element and draws both routes", async () => {
  const { hook, log, loading, mapEl } = fixture()
  await hook.mounted()
  assert.equal(log.maps.length, 1)
  assert.equal(log.maps[0].options.container, mapEl)
  log.maps[0].handlers.load()
  assert.ok(log.sources.includes("map-matching-demo-original"))
  assert.ok(log.sources.includes("map-matching-demo-matched"))
  assert.ok(log.layers.includes("map-matching-demo-endpoints"))
  assert.equal(loading.removed, true)
})

test("switching to the original path updates the buttons and the layer opacity", async () => {
  const { hook, log, buttons } = fixture()
  await hook.mounted()
  log.maps[0].handlers.load()
  buttons[0].click()
  assert.equal(buttons[0].attrs["aria-pressed"], "true")
  assert.equal(buttons[1].attrs["aria-pressed"], "false")
  assert.equal(
    log.maps[0].paint["map-matching-demo-original-halo:line-opacity"],
    0.85,
  )
})

test("removes the map and its listeners when destroyed", async () => {
  const { hook, log, buttons } = fixture()
  await hook.mounted()
  hook.destroyed()
  assert.equal(log.removed, 1)
  assert.equal(buttons[0].listeners.click, undefined)
})

test("decodes the matched path the same way as the Rails demo", () => {
  assert.equal(demo.ORIGINAL_PATH.length, 30)
  assert.ok(demo.MATCHED_PATH.length > 100)
  const [lng, lat] = demo.MATCHED_PATH[0]
  assert.ok(lng > 13.3 && lng < 13.5 && lat > 52.5 && lat < 52.6)
})
