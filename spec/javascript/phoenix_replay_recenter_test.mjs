import assert from "node:assert/strict"
import test from "node:test"
import { createReplay } from "../../app-phoenix/assets/js/map/replay/runtime.js"

test("replay recenter returns to its current marker before playback and releases camera listeners", async () => {
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map(),
    movements = []
  const map = {
    getSource: (id) => sources.get(id),
    addSource: (id, source) => sources.set(id, { ...source, setData() {} }),
    removeSource: (id) => sources.delete(id),
    getLayer: (id) => layers.get(id),
    addLayer: (layer) => layers.set(layer.id, layer),
    removeLayer: (id) => layers.delete(id),
    on: (event, fn) => listeners.set(event, fn),
    off: (event) => listeners.delete(event),
    easeTo: (options) => movements.push(options),
  }
  const replay = createReplay({
    map,
    timezone: "UTC",
    loadDay: async () => [
      { timestamp: 1774861200, longitude: 13, latitude: 52 },
    ],
  })
  await replay.open({})
  replay.recenter()
  assert.deepEqual(movements[0], { center: [13, 52], duration: 400 })
  assert.equal(listeners.has("wheel"), true)
  replay.close()
  assert.equal(listeners.size, 0)
})
