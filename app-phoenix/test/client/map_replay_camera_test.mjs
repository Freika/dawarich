import assert from "node:assert/strict"
import test from "node:test"
import { createReplay } from "../../assets/js/map/replay/runtime.js"

function fakeMap(zoom) {
  const layers = []
  const sources = new Map()
  const flights = []
  return {
    layers,
    flights,
    addSource: (id, source) => sources.set(id, source),
    getSource: (id) => sources.has(id) && { setData() {} },
    removeSource: (id) => sources.delete(id),
    addLayer: (layer) => layers.push(layer),
    getLayer: (id) => layers.find((layer) => layer.id === id),
    removeLayer: (id) => layers.splice(layers.findIndex((l) => l.id === id), 1),
    on() {},
    off() {},
    getZoom: () => zoom,
    flyTo: (options) => flights.push(options),
  }
}

const point = (timestamp, lon) => ({
  geometry: { coordinates: [lon, 52.5] },
  properties: { timestamp },
})

test("replay flies to the shown point like Rails and draws the orange pulsing marker", async () => {
  const map = fakeMap(12)
  const replay = createReplay({
    map,
    timezone: "UTC",
    loadDay: async () => [
      point("2026-06-01T08:00:00Z", 13.4),
      point("2026-06-01T09:00:00Z", 13.5),
    ],
    raf: () => 1,
    cancelRaf() {},
  })
  await replay.open({})
  assert.deepEqual(map.flights.at(-1), { center: [13.4, 52.5], zoom: 14, duration: 100 })
  replay.seek(540)
  assert.deepEqual(map.flights.at(-1), { center: [13.5, 52.5], zoom: 14, duration: 500 })
  assert.deepEqual(
    map.layers.map((layer) => [layer.id, layer.paint["circle-color"]]),
    [
      ["native-replay-marker-pulse", "#f97316"],
      ["native-replay-marker", "#f97316"],
    ],
  )
  replay.close()
  assert.deepEqual(map.layers, [])
})
