import assert from "node:assert/strict"
import test from "node:test"
import { installMapDiagnostics } from "../../app-phoenix/assets/js/map/runtime/diagnostics.js"

function setup() {
  const element = {}
  const rows = Array.from({ length: 700 }, (_, id) => ({
    id,
    type: "Feature",
    geometry: { type: "Point", coordinates: [13, 52] },
    properties: {
      name: "Synthetic",
      api_key: "synthetic-private",
      authorization: "synthetic-private",
      id,
    },
  }))
  const map = {
    getCenter: () => ({ lng: 13, lat: 52 }),
    getZoom: () => 5,
    getBearing: () => 0,
    getPitch: () => 0,
    getProjection: () => ({ type: "mercator" }),
    getStyle: () => ({
      sources: {
        "points-mvt-source": {
          tiles: ["https://tiles.test/?token=synthetic-private"],
        },
      },
      layers: [
        {
          id: "points",
          type: "circle",
          source: "points-mvt-source",
          layout: { visibility: "visible" },
          paint: { "circle-color": "#112233" },
        },
      ],
    }),
    querySourceFeatures: () => rows,
  }
  let state = {
    revision: 2,
    range: { timezone: "UTC", startAt: "2026-10-01", endAt: "2026-10-02" },
    styleName: "dark",
    api_key: "synthetic-private",
    namespace: "synthetic-private",
  }
  const destroy = installMapDiagnostics({
    element,
    map,
    getConfig: () => state,
  })
  return {
    element,
    map,
    destroy,
    update: () => {
      state = { ...state, revision: 3 }
    },
  }
}

test("root map diagnostics are bounded plain data and never expose a mutable map or credentials", () => {
  const { element, update, destroy } = setup()
  const snapshot = element.dawarichMapSnapshot({
    sourceId: "points-mvt-source",
    sourceLayer: "points",
  })
  assert.equal(snapshot.features.length, 500)
  assert.equal(snapshot.featureCount, 700)
  assert.equal(snapshot.hasSource, true)
  assert.deepEqual(snapshot.center, { lng: 13, lat: 52 })
  assert.equal(snapshot.zoom, 5)
  assert.equal(snapshot.layers[0].id, "points")
  assert.equal(snapshot.layers[0].paint["circle-color"], "#112233")
  assert.equal(snapshot.revision, 2)
  assert.equal(JSON.stringify(snapshot).includes("synthetic-private"), false)
  assert.equal(snapshot.map, undefined)
  assert.equal(snapshot.destroy, undefined)
  snapshot.features[0].geometry.coordinates[0] = 100
  assert.deepEqual(
    element.dawarichMapSnapshot({ sourceId: "points-mvt-source" }).features[0]
      .geometry.coordinates,
    [13, 52],
  )
  update()
  assert.equal(element.dawarichMapSnapshot().revision, 3)
  destroy()
})

test("diagnostic disposal removes only its owned root capability and stale reads return no map data", () => {
  const first = setup()
  const second = setup()
  const stale = first.element.dawarichMapSnapshot
  first.destroy()
  assert.equal(first.element.dawarichMapSnapshot, undefined)
  assert.equal(stale(), null)
  assert.equal(second.element.dawarichMapSnapshot().zoom, 5)
  const replacement = () => "replacement"
  second.element.dawarichMapSnapshot = replacement
  second.destroy()
  assert.equal(second.element.dawarichMapSnapshot, replacement)
})
