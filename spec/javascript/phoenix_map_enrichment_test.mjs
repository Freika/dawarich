import assert from "node:assert/strict"
import { test } from "node:test"
import { createEnrichmentTool } from "../../app-phoenix/assets/js/map/ui/enrichment.js"

function fixture() {
  const sources = new Map()
  const layers = new Set()
  const handlers = new Map()
  const timers = new Map()
  const popups = []
  const pushed = []
  let next = 0
  const map = {
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
    on: (type, layer, fn) => handlers.set(`${type}:${layer}`, fn),
    off: (type, layer, fn) =>
      handlers.get(`${type}:${layer}`) === fn &&
      handlers.delete(`${type}:${layer}`),
  }
  const tool = createEnrichmentTool({
    map,
    pushEvent: (event, payload) => pushed.push([event, payload]),
    timers: {
      setTimeout: (fn) => {
        next += 1
        timers.set(next, fn)
        return next
      },
      clearTimeout: (id) => timers.delete(id),
    },
    createPopup: (feature) => {
      const popup = {
        feature,
        removed: false,
        remove: () => {
          popup.removed = true
        },
      }
      popups.push(popup)
      return popup
    },
  })
  return { tool, sources, layers, handlers, timers, popups, pushed }
}

const match = (id) => ({ immich_asset_id: id, latitude: 52.5, longitude: 13.4 })

test("destroy cancels enrichment requests debounce timers and tooltips", () => {
  const f = fixture()
  f.tool.rangeChanged({ start_date: "2026-01-01" })
  f.tool.rangeChanged({ start_date: "2026-02-01" })
  assert.equal(f.timers.size, 1)
  for (const [id, fn] of [...f.timers]) {
    f.timers.delete(id)
    fn()
  }
  assert.deepEqual(f.pushed, [
    ["enrichment:scan", { start_date: "2026-02-01" }],
  ])

  f.tool.matches({ matches: [match("a"), match("b")] })
  assert.equal(f.layers.size, 1)
  assert.equal(
    f.sources.get("native-enrichment-matches").data.features.length,
    2,
  )
  f.handlers.get("mouseenter:native-enrichment-matches")({
    features: [{ properties: { id: "a" } }],
  })
  assert.equal(f.popups.length, 1)

  f.tool.rangeChanged({ start_date: "2026-03-01" })
  f.tool.destroy()
  assert.equal(f.timers.size, 0)
  assert.equal(f.popups[0].removed, true)
  assert.equal(f.layers.size, 0)
  assert.equal(f.sources.size, 0)
  assert.equal(f.handlers.size, 0)
  f.tool.matches({ matches: [match("late")] })
  f.tool.rangeChanged({ start_date: "2026-04-01" })
  assert.equal(f.layers.size, 0)
  assert.equal(f.timers.size, 0)
  assert.equal(f.pushed.length, 1)
})

test("a range change clears markers from the previous scan", () => {
  const f = fixture()
  f.tool.matches({ matches: [match("a")] })
  f.tool.rangeChanged({ start_date: "2026-05-01" })
  assert.equal(f.layers.size, 0)
  assert.equal(f.sources.size, 0)
})
