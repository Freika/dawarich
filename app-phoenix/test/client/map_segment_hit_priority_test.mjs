import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "../../../spec/javascript/support/native_m6_host_fixture.mjs"

test("a selected segment wins over its whole-track tile hit regardless of layer order", async () => {
  const f = fixture({ tracksEnabled: true })
  const row = new Element()
  f.nodes.set('.segment-leg[data-native-segment-id="19"]', row)
  const coordinates = [[12, 51], [13, 52], [14, 53]]
  const segment = coordinates.slice(1)
  f.reader.read = async () => ({ data: {
    type: "Feature",
    geometry: { type: "LineString", coordinates },
    properties: { id: 7, segments: [{ id: 19, start_index: 1, end_index: 2 }] },
  } })
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7 })
    const tile = { layer: { id: "tracks-mvt" }, properties: { id: 7 } }
    const selected = { layer: { id: "native-selected-track-segments" }, properties: { id: 19, track_id: 7 } }
    for (const hits of [[tile, selected], [selected, tile]]) {
      f.map.queryRenderedFeatures = () => hits
      f.map.emit("mousemove", { point: { x: 20, y: 30 } })
      await new Promise(resolve => setImmediate(resolve))
      assert.deepEqual(f.sources.get("native-timeline-hover").data.geometry.coordinates, segment)
      assert.equal(row.classList.contains("highlighted"), true)
      f.map.emit("mouseleave")
      assert.equal(row.classList.contains("highlighted"), false)
    }
    f.map.queryRenderedFeatures = () => [tile]
    f.map.emit("mousemove", { point: { x: 20, y: 30 } })
    await new Promise(resolve => setImmediate(resolve))
    assert.deepEqual(f.sources.get("native-timeline-hover").data.geometry.coordinates, coordinates)
  } finally {
    f.owner.destroy()
  }
})
