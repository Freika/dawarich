import assert from "node:assert/strict"
import { test } from "node:test"
import { FlightsLayer } from "../../app-phoenix/assets/js/map/layers/flights.js"
import { DayRoutesLayer } from "../../app-phoenix/assets/js/map/trip/days.js"
import {
  createTripLayers,
  groupDays,
} from "../../app-phoenix/assets/js/map/trip/layers.js"

const point = (id, stamp, longitude = 13) => ({
  id,
  timestamp: Date.parse(stamp) / 1000,
  latitude: 52,
  longitude,
})
function fixture() {
  const sources = new Map(),
    layers = new Map(),
    events = new Map(),
    paints = new Map(),
    popups = []
  const map = {
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    addSource(id, s) {
      sources.set(id, {
        ...s,
        setData(data) {
          this.data = data
        },
      })
    },
    removeSource: (id) => sources.delete(id),
    addLayer: (l) => layers.set(l.id, l),
    removeLayer: (id) => layers.delete(id),
    getCanvas: () => ({ style: {} }),
    setLayoutProperty() {},
    setPaintProperty(id, k, v) {
      paints.set(`${id}:${k}`, v)
    },
    fitBounds() {},
    on(e, a, b) {
      const key = b ? `${e}:${a}` : e
      events.set(key, new Set([...(events.get(key) ?? []), b ?? a]))
    },
    off(e, a, b) {
      events.get(b ? `${e}:${a}` : e)?.delete(b ?? a)
    },
  }
  class LngLatBounds {
    constructor() {
      this.coords = []
    }
    extend(p) {
      this.coords.push(p)
      return this
    }
    isEmpty() {
      return !this.coords.length
    }
  }
  class Popup {
    constructor() {
      popups.push(this)
    }
    setLngLat() {
      return this
    }
    setHTML() {
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  const library = { LngLatBounds, Popup }
  return { map, library, sources, layers, events, paints, popups }
}
test("trip day routes preserve profile day colors and saved gap settings", () => {
  const f = fixture(),
    points = [
      point(1, "2026-03-28T23:10Z"),
      point(2, "2026-03-28T23:15Z", 13.001),
      point(3, "2026-03-29T23:10Z"),
      point(4, "2026-03-29T23:15Z", 13.002),
    ]
  const days = groupDays(points, "Europe/Berlin")
  assert.deepEqual(Object.keys(days), ["2026-03-29", "2026-03-30"])
  const layer = new DayRoutesLayer(f.map, { library: f.library })
  layer.addDayRoutes(days, {
    timeThresholdMinutes: 1,
    distanceThresholdMeters: 500,
  })
  assert.equal(f.sources.get("day-route-2026-03-29").data.features.length, 0)
  layer.remove()
  layer.addDayRoutes(days, {
    timeThresholdMinutes: 60,
    distanceThresholdMeters: 500,
  })
  assert.equal(f.sources.get("day-route-2026-03-29").data.features.length, 1)
  assert.notEqual(
    layer.getDayColor("2026-03-29"),
    layer.getDayColor("2026-03-30"),
  )
  layer.selectDay("2026-03-29")
  assert.equal(f.paints.get("day-route-layer-2026-03-30:line-opacity"), 0.25)
  layer.remove()
})
test("trip style replacement retains selected day without duplicate interactions", () => {
  const f = fixture()
  const owner = createTripLayers({ ...f, onDay() {} })
  const data = {
    config: {
      range: { timezone: "UTC" },
      routeOptions: { timeThresholdMinutes: 60, distanceThresholdMeters: 500 },
    },
    path: [
      [13, 52],
      [14, 53],
    ],
    plan: null,
  }
  const points = [
    point(1, "2026-03-29T01:00Z"),
    point(2, "2026-03-29T01:01Z", 13.001),
    point(3, "2026-03-30T01:00Z"),
    point(4, "2026-03-30T01:01Z", 13.001),
  ]
  owner.update(data, { points }, {})
  owner.selectDay("2026-03-29")
  f.sources.clear()
  f.layers.clear()
  f.paints.clear()
  for (const fn of f.events.get("style.load")) fn()
  assert.equal(f.paints.get("day-route-layer-2026-03-30:line-opacity"), 0.25)
  assert.equal(f.events.get("click:day-route-layer-2026-03-29").size, 1)
  owner.destroy()
  assert.equal(
    [...f.events.values()].reduce((n, s) => n + s.size, 0),
    0,
  )
})
test("trip flight popup closes with its owned layer", () => {
  const f = fixture()
  const layer = new FlightsLayer(f.map, { library: f.library })
  layer.add({ type: "FeatureCollection", features: [] })
  layer._onClick({
    features: [{ properties: { from_code: "AAA", to_code: "BBB" } }],
    lngLat: [13, 52],
  })
  layer.remove()
  assert.equal(f.popups[0].removed, true)
})
