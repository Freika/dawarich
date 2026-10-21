import assert from "node:assert/strict"
import test from "node:test"
import { AreasLayer } from "../../assets/js/map/layers/areas.js"
import { PlacesLayer } from "../../assets/js/map/layers/places.js"
import { VisitsLayer } from "../../assets/js/map/layers/visits.js"

function fakeMap(ids) {
  const layers = ids.map((id) => ({ id }))
  const sources = new Map()
  return {
    layers,
    addSource: (id, config) => sources.set(id, config),
    getSource: (id) => sources.get(id),
    addLayer(layer, before) {
      const index = before ? layers.findIndex((l) => l.id === before) : -1
      if (index === -1) layers.push(layer)
      else layers.splice(index, 0, layer)
    },
    getLayer: (id) => layers.find((l) => l.id === id),
    getStyle: () => ({ layers }),
    setLayoutProperty() {},
    setPaintProperty() {},
    setFilter() {},
    on() {},
    off() {},
  }
}

const empty = { type: "FeatureCollection", features: [] }

test("lazily added layers take the Rails stacking order below tracks and points", () => {
  const map = fakeMap(["background", "places_locality", "tracks-mvt", "points-mvt-heatmap", "points-mvt", "recent-point"])
  new PlacesLayer(map).add(empty)
  new VisitsLayer(map).add(empty)
  new AreasLayer(map).add(empty)
  assert.deepEqual(
    map.layers.map((l) => l.id),
    [
      "background",
      "places_locality",
      "areas-fill",
      "areas-outline",
      "areas-labels",
      "visits-day-route",
      "visits-halo",
      "visits",
      "visits-labels",
      "places",
      "places-labels",
      "tracks-mvt",
      "points-mvt-heatmap",
      "points-mvt",
      "recent-point",
    ].filter((id) => map.getLayer(id)),
  )
  assert.ok(map.layers.findIndex((l) => l.id === "visits") < map.layers.findIndex((l) => l.id === "tracks-mvt"))
  assert.ok(map.layers.findIndex((l) => l.id === "places") < map.layers.findIndex((l) => l.id === "tracks-mvt"))
})
