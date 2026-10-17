import assert from "node:assert/strict"
import { test } from "node:test"
import { createStatsLayer } from "../../app-phoenix/assets/js/map/public/stats.js"

test("public stats hover and localized popup are owned across style reset and removal", () => {
  const sources = new Map(),
    layers = new Map(),
    handlers = new Map()
  let hovered,
    closed = 0,
    text = ""
  const map = {
    addSource: (id, s) => sources.set(id, s),
    getSource: (id) => sources.get(id),
    removeSource: (id) => sources.delete(id),
    addLayer: (l) => layers.set(l.id, l),
    getLayer: (id) => layers.get(id),
    removeLayer: (id) => layers.delete(id),
    on: (name, _id, f) => handlers.set(name, f),
    off: (name) => handlers.delete(name),
    getCanvas: () => ({ style: {} }),
    setFeatureState: (_, s) => {
      hovered = s.hover
    },
  }
  const library = {
    Popup: class {
      setLngLat() {
        return this
      }
      setText(value) {
        text = value
        return this
      }
      addTo() {
        return this
      }
      remove() {
        closed++
      }
    },
  }
  const owner = createStatsLayer({
    map,
    library,
    locale: "de",
    timezone: "Europe/Berlin",
    labels: {
      "map_info.points": "Punkte",
      "map_info.location_data": "Ortsdaten",
      "map_info.time_range": "Zeitraum",
    },
  })
  const data = {
    features: [
      {
        id: 3,
        properties: {
          point_count: 4,
          earliest_point: "2026-04-20T23:00Z",
          latest_point: "2026-04-21T00:00Z",
        },
      },
    ],
  }
  owner.show(data)
  handlers.get("mousemove")({ features: data.features })
  assert.equal(hovered, true)
  handlers.get("click")({ features: data.features, lngLat: [13, 52] })
  assert.match(text, /Punkte: 4/)
  assert.equal(text.match(/21\.4\.2026/g)?.length, 2)
  owner.show(data)
  assert.equal(closed, 1)
  assert.equal(handlers.size, 3)
  owner.destroy()
  assert.equal(handlers.size, 0)
  assert.equal(layers.size, 0)
  assert.equal(sources.size, 0)
})
