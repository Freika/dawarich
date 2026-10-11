import assert from "node:assert/strict"
import { test } from "node:test"
import {
  areasToGeoJSON,
  placesToGeoJSON,
  visitsToGeoJSON,
} from "../../app-phoenix/assets/js/map/data/entity_geojson.js"
import { AnomaliesLayer } from "../../app-phoenix/assets/js/map/layers/anomalies.js"
import { AreasLayer } from "../../app-phoenix/assets/js/map/layers/areas.js"
import { PlacesLayer } from "../../app-phoenix/assets/js/map/layers/places.js"
import { SelectedPointsLayer } from "../../app-phoenix/assets/js/map/layers/selected_points.js"
import { VisitsLayer } from "../../app-phoenix/assets/js/map/layers/visits.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
function fixture() {
  const sources = new Map(),
    layers = new Map(),
    filters = new Map()
  const map = {
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    addSource(id, source) {
      sources.set(id, {
        ...source,
        setData(data) {
          this.data = data
        },
      })
    },
    removeSource(id) {
      sources.delete(id)
    },
    addLayer(layer) {
      layers.set(layer.id, layer)
    },
    removeLayer(id) {
      layers.delete(id)
    },
    setLayoutProperty() {},
    setFilter(id, filter) {
      filters.set(id, filter)
    },
  }
  return { map, sources, layers, filters }
}

test("visit source updates retain chronological day route and independent status halo filters", () => {
  const f = fixture(),
    visits = new VisitsLayer(f.map)
  const data = visitsToGeoJSON([
    {
      id: 4,
      name: "visit",
      place: { name: "Place", latitude: 52, longitude: 13 },
      status: "suggested",
      started_at: "2026-03-29T00:00:00Z",
      ended_at: "2026-03-29T01:00:00Z",
      duration: 3600,
    },
  ])
  visits.add(data)
  visits.setSelectedVisit(4)
  visits.setStatusFilter({ confirmed: false, suggested: true, declined: false })
  visits.setDayRoute([
    { lng: 13, lat: 52 },
    { lng: 14, lat: 53 },
  ])
  visits.update(visitsToGeoJSON([]))
  assert.deepEqual(
    f.sources.get(visits.dayRouteSourceId).data.features[0].geometry
      .coordinates,
    [
      [13, 52],
      [14, 53],
    ],
  )
  assert.deepEqual(f.filters.get(visits.haloLayerId), ["==", ["get", "id"], 4])
  assert.deepEqual(f.filters.get(visits.labelsLayerId), [
    "match",
    ["get", "status"],
    ["suggested"],
    true,
    false,
  ])
  assert.equal(data.features[0].properties.duration, 3600)
  assert.equal(data.features[0].properties.place_name, "Place")
  visits.setStatusFilter({
    confirmed: false,
    suggested: false,
    declined: false,
  })
  assert.deepEqual(f.filters.get(visits.id), [
    "==",
    ["get", "status"],
    "__none__",
  ])
  visits.remove()
  assert.equal(f.sources.size, 0)
  assert.equal(f.layers.size, 0)
})

test("entity projections retain tag color locked names and circular radius", () => {
  const place = placesToGeoJSON([
    {
      id: 8,
      name: "<place>",
      note: "note",
      longitude: 13,
      latitude: 52,
      name_locked: true,
      tags: [{ id: 1, color: "#123456" }],
    },
  ]).features[0]
  assert.equal(place.properties.color, "#123456")
  assert.equal(place.properties.nameLocked, true)
  assert.deepEqual(JSON.parse(place.properties.tags), [
    { id: 1, color: "#123456" },
  ])
  const area = areasToGeoJSON([
    { id: 5, name: "Circle", longitude: "13", latitude: "52", radius: "100" },
  ]).features[0]
  assert.equal(area.geometry.coordinates[0].length, 65)
  assert.deepEqual(
    area.geometry.coordinates[0][0],
    area.geometry.coordinates[0].at(-1),
  )
  assert.ok(
    Math.abs(area.geometry.coordinates[0][16][1] - 52 - 100 / 110540) < 1e-10,
  )
  const f = fixture(),
    places = new PlacesLayer(f.map),
    areas = new AreasLayer(f.map)
  places.add({ type: "FeatureCollection", features: [place] })
  areas.add({ type: "FeatureCollection", features: [area] })
  assert.equal(f.layers.size, 5)
  places.remove()
  areas.remove()
  assert.equal(f.sources.size, 0)
})

test("selection retains anomaly identities and clears only its own highlights", () => {
  const f = fixture(),
    selected = new SelectedPointsLayer(f.map),
    place = new PlacesLayer(f.map)
  selected.add({ type: "FeatureCollection", features: [] })
  place.add({ type: "FeatureCollection", features: [] })
  selected.updateSelectedPoints({
    type: "FeatureCollection",
    features: [
      { properties: { id: 5, anomaly: true } },
      { properties: { id: 6 } },
    ],
  })
  assert.deepEqual(selected.getSelectedPointIds(), [5, 6])
  assert.equal(selected.getCount(), 2)
  selected.clearSelection()
  assert.equal(selected.getCount(), 0)
  assert.deepEqual(f.sources.get(selected.sourceId).data.features, [])
  assert.ok(f.sources.has(place.sourceId))
  selected.remove()
  place.remove()
})

test("removed anomalies stop owned pages and preserve exact request filters", async () => {
  const f = fixture(),
    pending = deferred()
  let signal
  const anomalies = new AnomaliesLayer(f.map, {
    reader: {
      pages(kind, params, options) {
        assert.equal(kind, "points")
        assert.deepEqual(params, {
          start_at: "2026-03-29",
          end_at: "2026-03-30",
          import_id: 8,
          anomalies_only: "true",
          slim: "true",
          order: "asc",
        })
        signal = options.signal
        return pending.promise
      },
    },
  })
  const read = anomalies.fetchAnomalies({
    start_at: "2026-03-29",
    end_at: "2026-03-30",
    import_id: 8,
  })
  anomalies.remove()
  assert.equal(signal.aborted, true)
  pending.resolve([{ id: 4, latitude: 52, longitude: 13, accuracy: 500 }])
  await assert.rejects(read, { name: "AbortError" })
  const data = anomalies._pointsToGeoJSON([
    {
      id: 4,
      latitude: 52,
      longitude: 13,
      timestamp: 1790000000,
      accuracy: 500,
      velocity: 20,
    },
  ])
  assert.deepEqual(data.features[0].properties, {
    id: 4,
    timestamp: 1790000000,
    accuracy: 500,
    velocity: 20,
  })
  assert.deepEqual(data.features[0].geometry.coordinates, [13, 52])
  assert.equal(anomalies.visible, false)
  const labels = {
    "anomalies.low_accuracy": "Low {accuracy}/{threshold}",
    "anomalies.impossible_speed": "Impossible",
  }
  assert.equal(
    AnomaliesLayer.anomalyReason({ accuracy: 101 }, labels),
    "Low 101/100",
  )
  assert.equal(
    AnomaliesLayer.anomalyReason({ accuracy: 100 }, labels),
    "Impossible",
  )
})
