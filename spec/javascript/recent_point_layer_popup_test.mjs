import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/recent_point_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const dependencies = `
  const formatDateTime = (ms) => "at " + ms;
  const escapeHtml = (value) => String(value);
  const maplibregl = {
    Popup: class {
      setLngLat(lngLat) { this.lngLat = lngLat; return this }
      setHTML(html) { this.html = html; return this }
      addTo() { this.open = true; return this }
      remove() { this.open = false }
    },
  };
  class BaseLayer {
    constructor(map, options) { this.map = map; this.id = options.id; }
    add(data) { this.data = data; }
    remove() { this.data = null; }
  }
`
const { RecentPointLayer } = await import(
  `data:text/javascript;base64,${Buffer.from(dependencies + source.replace(/^import .*\n/gm, "")).toString("base64")}`
)

function fakeMap() {
  const handlers = {}
  return {
    handlers,
    on(event, layerId, handler) {
      handlers[`${event}:${layerId}`] = handler
    },
    off(event, layerId) {
      delete handlers[`${event}:${layerId}`]
    },
    getCanvas: () => ({ style: {} }),
  }
}

test("hovering the dot shows its title and the time of the point", () => {
  const map = fakeMap()
  const layer = new RecentPointLayer(map, { hoverTitle: "Your latest point" })
  layer.add({ type: "FeatureCollection", features: [] })

  map.handlers["mouseenter:recent-point"]({
    lngLat: [13.4, 52.5],
    features: [{ properties: { timestamp: 1758196800 } }],
  })

  assert.equal(layer._popup.open, true)
  assert.match(layer._popup.html, /Your latest point/)
  assert.match(layer._popup.html, /at 1758196800000/)

  map.handlers["mouseleave:recent-point"]()
  assert.equal(layer._popup.open, false)
})

test("the dot has no hover popup without a title", () => {
  const map = fakeMap()
  const layer = new RecentPointLayer(map)
  layer.add({ type: "FeatureCollection", features: [] })

  assert.deepEqual(Object.keys(map.handlers), [])
})

test("removing the layer detaches its hover handlers", () => {
  const map = fakeMap()
  const layer = new RecentPointLayer(map, { hoverTitle: "Your latest point" })
  layer.add({ type: "FeatureCollection", features: [] })
  layer.remove()

  assert.deepEqual(Object.keys(map.handlers), [])
})
