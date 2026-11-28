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
const moduleUrl = `data:text/javascript;base64,${Buffer.from((await read("place_editor_state")) + strip(await read("selected_place_layer"))).toString("base64")}`
const { SelectedPlaceLayer } = await import(moduleUrl)
const place = {
  id: 2,
  longitude: 13.4,
  latitude: 52.5,
  visit_radius: 125,
  geofence: true,
}

function setup(onClick) {
  const sources = new Map()
  const layers = new Map()
  const listeners = new Map()
  let ready = true
  const map = {
    on: (event, ...args) => listeners.set(event, args.at(-1)),
    off: (event) => listeners.delete(event),
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
    isStyleLoaded: () => ready,
  }
  return {
    selection: new SelectedPlaceLayer(map, onClick),
    layers,
    sources,
    listeners,
    ready: (value) => {
      ready = value
    },
  }
}

test("selected place updates and clears its own source without touching regular Places", () => {
  const { selection, sources, layers, listeners } = setup()
  selection.show(place)
  assert.equal(sources.size, 1)
  assert.equal(layers.size, 3)
  assert.ok(layers.has("selected-place"))
  selection.show({ ...place, longitude: 13.5 })
  assert.deepEqual(
    sources.get("selected-place").data.features[0].geometry.coordinates,
    [13.5, 52.5],
  )
  selection.clear()
  assert.equal(sources.size, 0)
  assert.equal(layers.size, 0)
  for (const [type, listener] of listeners) {
    if (type !== "click") listener()
  }
  assert.equal(sources.size, 0)
  selection.destroy()
  assert.equal(listeners.size, 0)
})

test("selected place waits for a loaded style and returns after a style replacement", () => {
  const { selection, sources, layers, listeners, ready } = setup()
  ready(false)
  selection.show(place)
  assert.equal(sources.size, 0)
  listeners.get("styledata")?.()
  assert.equal(sources.size, 0)
  ready(true)
  listeners.get("render")?.()
  assert.equal(sources.size, 1)
  sources.clear()
  layers.clear()
  listeners.get("render")?.()
  assert.equal(layers.size, 3)
  selection.destroy()
})

test("clicking the highlighted place opens it even when the regular Places layer is absent", () => {
  const opened = []
  const { selection, listeners } = setup((id) => opened.push(id))
  selection.show(place)
  listeners.get("click")?.({ features: [{ properties: { id: 2 } }] })
  assert.deepEqual(opened, [2])
  selection.destroy()
  assert.equal(listeners.size, 0)
})
