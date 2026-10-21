import assert from "node:assert/strict"
import test from "node:test"
import { createBaseLayers } from "../../assets/js/map/layers/tile_layers.js"

function fakeMap() {
  const layers = []
  const sources = new Map()
  const handlers = {}
  return {
    layers,
    addSource: (id, config) => sources.set(id, config),
    getSource: (id) => sources.get(id),
    removeSource: (id) => sources.delete(id),
    addLayer(layer, before) {
      const index = before ? layers.findIndex((l) => l.id === before) : -1
      if (index === -1) layers.push(layer)
      else layers.splice(index, 0, layer)
    },
    getLayer: (id) => layers.find((l) => l.id === id),
    removeLayer(id) {
      layers.splice(
        layers.findIndex((l) => l.id === id),
        1,
      )
    },
    getStyle: () => ({ layers }),
    setLayoutProperty() {},
    setPaintProperty() {},
    filters: 0,
    setFilter() {
      this.filters++
    },
    on(name, handler) {
      handlers[name] = [...(handlers[name] ?? []), handler]
    },
    off() {},
    emit(name) {
      for (const handler of handlers[name] ?? []) handler()
    },
  }
}

const order = (map) =>
  map.layers.map((l) => l.id).filter((id) => /mvt/.test(id))
const railsOrder = ["tracks-mvt", "points-mvt-heatmap", "points-mvt"]
const config = (startAt) => ({
  range: { startAt, endAt: "2026-10-18T00:00" },
  pointsEnabled: true,
  heatmapEnabled: true,
  tracksEnabled: true,
})

test("the tracks layer sits below the points and heatmap layers, as on Rails", () => {
  const map = fakeMap()
  const base = createBaseLayers({ map, config: config("2026-10-16T00:00") })
  map.emit("style.load")
  assert.deepEqual(order(map), railsOrder)

  base.update(config("2026-10-15T00:00"))
  assert.deepEqual(order(map), railsOrder)

  for (const id of railsOrder) map.removeLayer(id)
  map.emit("style.load")
  assert.deepEqual(order(map), railsOrder)
  base.destroy()
})

test("an unchanged configuration sets no layer filter, so MapLibre keeps its tiles", () => {
  const map = fakeMap()
  const base = createBaseLayers({ map, config: config("2026-10-16T00:00") })
  map.emit("style.load")
  base.update(config("2026-10-16T00:00"))
  base.update(config("2026-10-16T00:00"))
  assert.equal(map.filters, 0)

  base.update({ ...config("2026-10-16T00:00"), flightWindows: [[1, 2]] })
  assert.equal(map.filters, 3)
  base.update({ ...config("2026-10-16T00:00"), flightWindows: [[1, 2]] })
  assert.equal(map.filters, 3)
  base.destroy()
})
