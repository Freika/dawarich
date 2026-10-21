import assert from "node:assert/strict"
import { test } from "node:test"
import {
  createSegmentHighlight,
  segmentLine,
} from "../../app-phoenix/assets/js/map/edit/segments.js"

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

const path = [
  [13.4, 52.5],
  [13.41, 52.51],
  [13.42, 52.52],
  [13.43, 52.53],
]

test("segment highlight draws one owned slice and clears it", () => {
  assert.deepEqual(segmentLine(path, { start_index: 1, end_index: 2 }), [
    [13.41, 52.51],
    [13.42, 52.52],
  ])
  assert.equal(segmentLine(path, { start_index: 3, end_index: 3 }), null)
  assert.equal(segmentLine(path, { start_index: null, end_index: 2 }), null)

  const map = mapMock()
  const highlight = createSegmentHighlight({ map })
  highlight.show(path, { start_index: 0, end_index: 2 })
  highlight.show(path, { start_index: 1, end_index: 3 })
  assert.equal(map.layers.size, 1)
  assert.deepEqual(
    map.sources.get("native-segment-highlight").data.geometry.coordinates[0],
    [13.41, 52.51],
  )
  highlight.clear()
  assert.equal(map.layers.size, 0)
  assert.equal(map.sources.size, 0)
  highlight.show(path, { start_index: 0, end_index: 1 })
  highlight.destroy()
  highlight.show(path, { start_index: 0, end_index: 1 })
  assert.equal(map.layers.size, 0)
  assert.equal(map.sources.size, 0)
})
