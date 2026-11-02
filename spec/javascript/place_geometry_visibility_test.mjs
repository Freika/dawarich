import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (name) =>
  readFile(
    new URL(
      `../../app/javascript/maps_maplibre/editing/${name}.js`,
      import.meta.url,
    ),
    "utf8",
  )
const strip = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const visibility = await read("place_edit_visibility")
const { PlacePanelBridge, selectedPlaceFeatures } = await import(
  `data:text/javascript;base64,${Buffer.from(`
const translate = (key) => key
const removePlaceFeature = () => {}
class PlaceCamera { cancel() {} fit() {} }
const maplibregl = { Marker: class {
  setLngLat(position) { this.position = position; return this }
  addTo() { return this }
  on() {}
  remove() {}
} }
${await read("place_editor_state")}
${strip(visibility)}
${strip(await read("selected_place_layer"))}
${strip(await read("place_geometry_editor"))}
${strip(await read("place_panel_bridge"))}
`).toString("base64")}`
)

const place = {
  id: 2,
  longitude: 13.4,
  latitude: 52.5,
  visit_radius: 125,
  geofence: true,
}
const regularIds = ["places-radius-fill", "places-radius-outline", "places"]

function matches(expression, properties) {
  if (!Array.isArray(expression)) return expression
  const [operator, ...args] = expression
  const value = (arg) => matches(arg, properties)
  if (operator === "get") return properties[args[0]]
  if (operator === "==") return value(args[0]) === value(args[1])
  if (operator === "!=") return value(args[0]) !== value(args[1])
  if (operator === "all") return args.every(value)
  throw new Error(`Unexpected operator ${operator}`)
}

function setup(visible) {
  const sources = new Map()
  const layers = new Map()
  const listeners = new Map()
  const events = new Map()
  const map = {
    on: (event, ...args) => {
      if (!listeners.has(event)) listeners.set(event, new Set())
      listeners.get(event).add(args.at(-1))
    },
    off: (event, ...args) => listeners.get(event)?.delete(args.at(-1)),
    getSource: (id) => sources.get(id),
    addSource: (id, source) =>
      sources.set(id, {
        ...source,
        setData(data) {
          this.data = data
        },
      }),
    removeSource: (id) => sources.delete(id),
    getLayer: (id) => layers.get(id),
    addLayer: (layer) => layers.set(layer.id, layer),
    removeLayer: (id) => layers.delete(id),
    getFilter: (id) => layers.get(id)?.filter,
    setFilter: (id, filter) => {
      layers.get(id).filter = filter
    },
    isStyleLoaded: () => true,
  }
  globalThis.window = { location: { href: "https://example.test/map/v2" } }
  globalThis.document = {
    createElement: () => ({ dataset: {}, setAttribute() {} }),
    dispatchEvent() {},
  }
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = type
      this.detail = options?.detail
    }
  }
  const bridge = new PlacePanelBridge({
    map,
    closeInfo() {},
    cleanup: {
      addEventListener: (_target, type, listener) => events.set(type, listener),
    },
  })
  bridge.open(place.id)
  bridge.loaded(place)
  const regular = () => {
    for (const id of regularIds)
      map.addLayer({
        id,
        filter: [
          "==",
          ["get", "featureKind"],
          id === "places" ? "center" : "boundary",
        ],
        layout: { visibility: visible ? "visible" : "none" },
      })
  }
  const render = () => {
    for (const listener of listeners.get("render") || []) listener()
  }
  const emit = (type, detail) => events.get(type)({ detail })
  return { bridge, map, sources, layers, regular, render, emit }
}

function expectRegular(layers, hidden, visible) {
  for (const id of regularIds) {
    const layer = layers.get(id)
    const featureKind = id === "places" ? "center" : "boundary"
    assert.equal(
      matches(layer.filter, { id: 2, featureKind }),
      !hidden,
      `${id} active place`,
    )
    assert.equal(
      matches(layer.filter, { id: 3, featureKind }),
      true,
      `${id} neighbouring place`,
    )
    assert.equal(layer.layout.visibility, visible ? "visible" : "none")
  }
}

test("map editing hides both place overlays through late loads and restores geometry on Cancel and Save", () => {
  for (const visible of [true, false])
    for (const late of [false, true]) {
      const { bridge, map, sources, layers, regular, render, emit } =
        setup(visible)
      if (!late) regular()
      emit("place:map-edit", { place, maximum: 50000 })
      if (late) regular()
      render()
      assert.equal(sources.has("selected-place"), false)
      assert.equal(sources.has("place-edit-radius"), true)
      expectRegular(layers, true, visible)
      regular()
      render()
      expectRegular(layers, true, visible)
      emit("place:map-cancel")
      assert.equal(sources.has("place-edit-radius"), false)
      assert.deepEqual(
        sources.get("selected-place").data.features[0].geometry.coordinates,
        [13.4, 52.5],
      )
      expectRegular(layers, false, visible)
      emit("place:map-edit", { place, maximum: 50000 })
      render()
      assert.equal(sources.has("selected-place"), false)
      expectRegular(layers, true, visible)
      const saved = { ...place, longitude: 13.5, visit_radius: 180 }
      bridge.loaded(saved)
      emit("place:updated", { place: saved })
      assert.equal(sources.has("place-edit-radius"), false)
      assert.deepEqual(
        sources.get("selected-place").data,
        selectedPlaceFeatures(saved),
      )
      expectRegular(layers, false, visible)
      emit("place:map-edit", { place: saved, maximum: 50000 })
      render()
      expectRegular(layers, true, visible)
      bridge.destroy()
      expectRegular(layers, false, visible)
      render()
      assert.equal(sources.has("selected-place"), false)
      assert.equal(map.getLayer("place-edit-line"), undefined)
    }
})
