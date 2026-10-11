import assert from "node:assert/strict"
import { test } from "node:test"
import { createTimelineHover } from "../../app-phoenix/assets/js/map/ui/timeline.js"

function mapMock() {
  const sources = new Map()
  const layers = new Set()
  return {
    sources,
    layers,
    addSource: (id, source) => sources.set(id, { ...source }),
    getSource: (id) =>
      sources.has(id) && {
        setData: (data) => {
          sources.get(id).data = data
        },
      },
    removeSource: (id) => sources.delete(id),
    addLayer: (layer) => layers.add(layer.id),
    getLayer: (id) => layers.has(id),
    removeLayer: (id) => layers.delete(id),
  }
}

const track = (id) => ({
  type: "Feature",
  properties: { id },
  geometry: {
    type: "LineString",
    coordinates: [
      [13, 52],
      [13.1, 52.1],
    ],
  },
})

test("timeline hover draws one layer and clears it after patch", () => {
  const map = mapMock()
  const hover = createTimelineHover({ map })
  hover.hover(track(1))
  hover.hover(track(2))
  assert.equal(map.layers.size, 1)
  assert.equal(map.sources.get("native-timeline-hover").data.properties.id, 2)
  hover.config({ revision: 4 })
  assert.equal(map.layers.size, 0)
  assert.equal(map.sources.size, 0)
  hover.hover(null)
  assert.equal(map.layers.size, 0)
  hover.hover(track(3))
  hover.destroy()
  hover.hover(track(4))
  assert.equal(map.layers.size, 0)
  assert.equal(map.sources.size, 0)
})
