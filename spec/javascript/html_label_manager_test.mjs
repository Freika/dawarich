import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const strip = (source) => source.replace(/^import .*\n/gm, "")
const source = await read("maps_maplibre/utils/html_label_manager.js")
const dependencies = `
  const document = { createElement: () => ({ style: {}, textContent: "" }) }
  const maplibregl = { Marker: class {
    constructor(options) { this.element = options.element }
    setLngLat(coords) { this.coords = coords; return this }
    addTo(map) { this.map = map; return this }
    getElement() { return this.element }
    setOpacity(value) { this.opacity = String(value); return this }
    remove() { this.removed = true }
  } }
`
const { HtmlLabelManager, VisitsLayer } = await import(
  `data:text/javascript;base64,${Buffer.from(
    dependencies +
      strip(source) +
      (await read("maps_maplibre/layers/base_layer.js")) +
      '\nconst getVisitMarkerColor = () => "green"\n' +
      strip(await read("maps_maplibre/layers/visits_layer.js")),
  ).toString("base64")}`
)
const feature = (id, name = "🏡 Home", status = "confirmed") => ({
  type: "Feature",
  geometry: { type: "Point", coordinates: [1, 2] },
  properties: { id, name, status },
})

test("native emoji text survives updates, and missing or unnamed features remove markers", () => {
  const labels = new HtmlLabelManager({})
  labels.sync([feature(1), feature(2)])
  const first = labels.markers.get(1)
  const second = labels.markers.get(2)
  assert.equal(first.getElement().textContent, "🏡 Home")
  labels.sync([feature(1, "🌳 Park")])
  assert.equal(labels.markers.get(1), first)
  assert.equal(first.getElement().textContent, "🌳 Park")
  assert.equal(second.removed, true)
  labels.sync([feature(1, "")])
  assert.equal(first.removed, true)
  assert.equal(labels.markers.size, 0)
})

test("visibility, filters and opacity apply to existing and newly synced markers", () => {
  const labels = new HtmlLabelManager({})
  labels.sync([feature(1), feature(2, "🌳 Park", "suggested")])
  labels.setFilter((f) => f.properties.status === "confirmed")
  labels.setOpacity((f) => (f.properties.id === 1 ? 1 : 0.15))
  const element = (id) => labels.markers.get(id).getElement()
  assert.equal(element(1).style.display, "")
  assert.equal(element(2).style.display, "none")
  assert.equal(element(2).style.opacity, "0.15")
  // Model MapLibre's repaint using its stored marker opacity.
  const dimmed = labels.markers.get(2)
  dimmed.getElement().style.opacity = dimmed.opacity
  assert.equal(element(2).style.opacity, "0.15")
  labels.setVisibility(false)
  assert.equal(element(1).style.display, "none")
  labels.setVisibility(true)
  assert.equal(element(1).style.display, "")
  assert.equal(element(2).style.display, "none")
  labels.sync([feature(3, "🧑 Ada", "suggested")])
  assert.equal(element(3).style.opacity, "0.15")
  assert.equal(element(3).style.display, "none")
  labels.setFilter(null)
  labels.setOpacity(null)
  assert.equal(element(3).style.display, "")
  assert.equal(element(3).style.opacity, "")
})

test("clear removes DOM markers and resets filter and opacity before style rebuild", () => {
  const labels = new HtmlLabelManager({})
  labels.sync([feature(1)])
  const marker = labels.markers.get(1)
  labels.setFilter(() => false)
  labels.setOpacity(() => 0.05)
  labels.clear()
  assert.equal(marker.removed, true)
  assert.equal(labels.markers.size, 0)
  labels.sync([feature(1)])
  const element = labels.markers.get(1).getElement()
  assert.equal(element.style.display, "")
  assert.equal(element.style.opacity, "")
})

test("visit labels follow status, layer visibility and opacity, and are cleared by remove", () => {
  const sources = new Map(),
    layers = new Map()
  const map = {
    getSource: (id) => sources.get(id),
    addSource: (id) => sources.set(id, { setData() {} }),
    removeSource: (id) => sources.delete(id),
    getLayer: (id) => layers.get(id),
    addLayer: (layer) => layers.set(layer.id, layer),
    removeLayer: (id) => layers.delete(id),
    setLayoutProperty() {},
    setFilter() {},
  }
  const visits = new VisitsLayer(map)
  visits.add({ features: [feature(1), feature(2, "🌳 Park", "suggested")] })
  assert.equal(
    [...layers.values()].some((layer) => layer.type === "symbol"),
    false,
  )
  visits.setStatusFilter({ suggested: false })
  assert.equal(visits.labels.markers.get(2).getElement().style.display, "none")
  visits.setVisibility(false)
  assert.equal(visits.labels.markers.get(1).getElement().style.display, "none")
  visits.setVisibility(true)
  visits.setLabelOpacity(() => 0.05)
  visits.update({ features: [feature(3)] })
  const marker = visits.labels.markers.get(3)
  assert.equal(marker.getElement().style.opacity, "0.05")
  visits.remove()
  assert.equal(marker.removed, true)
  assert.equal(sources.size, 0)
  assert.equal(layers.size, 0)
})
