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

test("native layer diagnostics retain bounded track metadata and paint expressions without credentials", () => {
  const element = {}
  const expression = ["coalesce", ["get", "color"], "#6366F1"]
  const row = {
    id: 7,
    type: "Feature",
    geometry: {
      type: "LineString",
      coordinates: [
        [13, 52],
        [14, 53],
      ],
    },
    properties: {
      id: 7,
      start_at: "2026-10-01T00:00:00Z",
      end_at: "2026-10-02T00:00:00Z",
      avg_speed: 12,
      distance: 100,
      duration: 300,
      color: "#6366F1",
      api_key: "synthetic-private",
    },
  }
  const destroy = installMapDiagnostics({
    element,
    getConfig: () => ({ revision: 1 }),
    map: {
      getStyle: () => ({
        sources: { tracks: {} },
        layers: [
          {
            id: "tracks",
            paint: {
              "line-color": expression,
              "secret-object": { api_key: "synthetic-private" },
            },
          },
        ],
      }),
      querySourceFeatures: () => [row],
    },
  })
  try {
    const snapshot = element.dawarichMapSnapshot({ sourceId: "tracks" })
    assert.equal(
      snapshot.features[0].properties.start_at,
      row.properties.start_at,
    )
    assert.equal(snapshot.features[0].properties.end_at, row.properties.end_at)
    assert.equal(snapshot.features[0].properties.avg_speed, 12)
    assert.deepEqual(snapshot.layers[0].paint["line-color"], expression)
    assert.equal(JSON.stringify(snapshot).includes("synthetic-private"), false)
    snapshot.layers[0].paint["line-color"][1][1] = "other"
    assert.equal(
      element.dawarichMapSnapshot().layers[0].paint["line-color"][1][1],
      "color",
    )
  } finally {
    destroy()
  }
})

test("native paint diagnostics bound expression depth width and total copied values", () => {
  const element = {}
  let nested = ["get", "color"]
  for (let n = 0; n < 10; n++) nested = [nested]
  const bulk = Array.from({ length: 64 }, () => Array(64).fill(1))
  const layers = Array.from({ length: 64 }, (_, id) => ({
    id: String(id),
    paint: {
      "line-color": ["get", "color"],
      deep: nested,
      wide: Array(129).fill(1),
      bulk,
    },
  }))
  const destroy = installMapDiagnostics({
    element,
    getConfig: () => ({}),
    map: { getStyle: () => ({ layers }) },
  })
  try {
    const snapshot = element.dawarichMapSnapshot()
    assert.deepEqual(snapshot.layers[0].paint["line-color"], ["get", "color"])
    assert.equal(snapshot.layers[0].paint.deep, undefined)
    assert.equal(snapshot.layers[0].paint.wide, undefined)
    const count = (value) =>
      1 +
      (Array.isArray(value)
        ? value.reduce((sum, part) => sum + count(part), 0)
        : 0)
    const total = snapshot.layers.reduce(
      (sum, layer) =>
        sum +
        Object.values(layer.paint).reduce((n, value) => n + count(value), 0),
      0,
    )
    assert.ok(total <= 4096)
  } finally {
    destroy()
  }
})

test("native point diagnostics project only visible finite point hit positions as copied data", () => {
  const f = setup()
  const screen = { x: 120, y: 80, map: f.map }
  f.map.project = () => screen
  f.map.getContainer = () => ({
    getBoundingClientRect: () => ({ width: 400, height: 300 }),
  })
  const read = () =>
    f.element.dawarichMapSnapshot({ sourceId: "points-mvt-source" }).features[0]
  assert.deepEqual(read().screen, { x: 120, y: 80 })
  read().screen.x = 999
  assert.equal(read().screen.x, 120)
  screen.x = 450
  assert.equal(read().screen, null)
  screen.x = Number.NaN
  assert.equal(read().screen, null)
  f.map.querySourceFeatures = () => [
    {
      geometry: {
        type: "LineString",
        coordinates: [
          [13, 52],
          [14, 53],
        ],
      },
    },
  ]
  assert.equal(read().screen, null)
  f.destroy()
})

test("diagnostic geometry hits retain bounded track and Area polygon locations", () => {
  const f = setup()
  f.map.project = ([x, y]) => ({ x, y })
  f.map.getContainer = () => ({
    getBoundingClientRect: () => ({ width: 100, height: 100 }),
  })
  f.map.querySourceFeatures = () => [
    {
      geometry: {
        type: "LineString",
        coordinates: [
          [13, 52],
          [15, 55],
          [20, 58],
        ],
      },
    },
    {
      geometry: {
        type: "Polygon",
        coordinates: [
          [
            [10, 50],
            [20, 50],
            [20, 60],
            [10, 60],
            [10, 50],
          ],
        ],
      },
    },
  ]
  try {
    const receipt = f.element.dawarichMapSnapshot({
      sourceId: "points-mvt-source",
    })
    assert.deepEqual(
      receipt.features.map((feature) => feature.screen),
      [
        { x: 15, y: 55 },
        { x: 15, y: 55 },
      ],
    )
  } finally {
    f.destroy()
  }
})
test("diagnostic geometry hits refuse malformed offscreen and unsupported coordinates", () => {
  const f = setup()
  f.map.project = ([x, y]) =>
    Math.abs(x) > 180 || Math.abs(y) > 90 ? { x: 25, y: 52 } : { x, y }
  f.map.getContainer = () => ({
    getBoundingClientRect: () => ({ width: 100, height: 100 }),
  })
  f.map.querySourceFeatures = () => [
    { geometry: { type: "LineString", coordinates: [[NaN, 52]] } },
    { geometry: { type: "LineString", coordinates: [[-10, 52]] } },
    { geometry: { type: "Polygon", coordinates: [[]] } },
    { geometry: { type: "Point", coordinates: [13, Infinity] } },
    { geometry: { type: "GeometryCollection", geometries: [] } },
    { geometry: { type: "LineString", coordinates: [[13, 120]] } },
    { geometry: { type: "Point", coordinates: [200, 52] } },
    { geometry: { type: "Polygon", coordinates: [[null]] } },
  ]
  try {
    assert.deepEqual(
      f.element
        .dawarichMapSnapshot({ sourceId: "points-mvt-source" })
        .features.map((feature) => feature.screen),
      [null, null, null, null, null, null, null, null],
    )
  } finally {
    f.destroy()
  }
})

test("owned visit halo diagnostics copy only bounded integer identity filters", () => {
  const f = setup()
  let filter = ["==", ["get", "id"], 7]
  f.map.getStyle = () => ({
    sources: {},
    layers: [{ id: "visits-halo", type: "circle", filter }],
  })
  try {
    const copied = f.element.dawarichMapSnapshot().layers[0].filter
    assert.deepEqual(copied, filter)
    copied[1][1] = "mutated"
    assert.equal(filter[1][1], "id")
    for (const invalid of [
      ["==", ["get", "api_key"], "synthetic-private"],
      ["==", ["get", "id"], Infinity],
      ["==", ["get", "id"], "7"],
    ]) {
      filter = invalid
      assert.equal(f.element.dawarichMapSnapshot().layers[0].filter, undefined)
      assert.equal(
        JSON.stringify(f.element.dawarichMapSnapshot()).includes(
          "synthetic-private",
        ),
        false,
      )
    }
  } finally {
    f.destroy()
  }
})

test("native viewport bounds diagnostics copy only finite coordinates and expire with their owner", () => {
  const f = setup()
  const box = { west: 12, south: 51, east: 14, north: 53 }
  f.map.getBounds = () => ({
    getWest: () => box.west,
    getSouth: () => box.south,
    getEast: () => box.east,
    getNorth: () => box.north,
    token: "synthetic-private",
  })
  const snapshot = f.element.dawarichMapSnapshot
  assert.deepEqual(snapshot().bounds, box)
  snapshot().bounds.west = 80
  assert.equal(snapshot().bounds.west, 12)
  for (const value of [NaN, Infinity, "synthetic-private"]) {
    box.west = value
    assert.equal(snapshot().bounds, null)
  }
  f.destroy()
  assert.equal(snapshot(), null)
})

test("native diagnostics copy owned GeoJSON input geometry and total count while bounding features", () => {
  const f = setup()
  const rows = Array.from({ length: 601 }, (_, id) => ({
    type: "Feature",
    properties: { id, api_key: "synthetic-private" },
    geometry: { type: "Point", coordinates: [13.401234567, 52.501234567] },
  }))
  f.map.getSource = () => ({
    serialize: () => ({
      type: "geojson",
      data: { type: "FeatureCollection", features: rows },
    }),
  })
  const result = f.element.dawarichMapSnapshot({
    sourceId: "points-mvt-source",
  })
  assert.equal(result.featureCount, 601)
  assert.equal(result.features.length, 500)
  assert.deepEqual(
    result.features[0].geometry.coordinates,
    [13.401234567, 52.501234567],
  )
  assert.equal(JSON.stringify(result).includes("synthetic-private"), false)
  result.features[0].geometry.coordinates[0] = 1
  assert.equal(rows[0].geometry.coordinates[0], 13.401234567)
  f.map.getSource = () => ({
    serialize: () => ({
      type: "geojson",
      data: "https://example.test/?token=synthetic-private",
    }),
  })
  const remote = f.element.dawarichMapSnapshot({
    sourceId: "points-mvt-source",
  })
  assert.equal(remote.featureCount, 700)
  assert.equal(JSON.stringify(remote).includes("synthetic-private"), false)
  f.destroy()
})

test("diagnostic hit positions require rendered source geometry instead of hidden tile geometry", () => {
  const f = setup()
  f.map.project = ([x, y]) => ({ x, y })
  f.map.getContainer = () => ({
    getBoundingClientRect: () => ({ width: 100, height: 100 }),
  })
  f.map.querySourceFeatures = () => [
    {
      type: "Feature",
      properties: { id: 7 },
      geometry: {
        type: "LineString",
        coordinates: [
          [10, 10],
          [20, 20],
          [30, 30],
        ],
      },
    },
  ]
  let rendered = []
  f.map.queryRenderedFeatures = (options) => {
    assert.deepEqual(options.layers, ["points"])
    return rendered
  }
  const read = () =>
    f.element.dawarichMapSnapshot({ sourceId: "points-mvt-source" }).features[0]
  assert.equal(read().screen, null)
  rendered = [
    {
      properties: { id: 7 },
      geometry: {
        type: "LineString",
        coordinates: [
          [40, 40],
          [50, 50],
          [60, 60],
        ],
      },
    },
  ]
  assert.deepEqual(read().screen, { x: 50, y: 50 })
  assert.deepEqual(read().geometry.coordinates, [
    [10, 10],
    [20, 20],
    [30, 30],
  ])
  f.destroy()
})

test("rendered multipart tracks and areas use an in-viewport component for browser hits", () => {
  const f = setup()
  f.map.project = ([x, y]) => ({ x, y })
  f.map.getContainer = () => ({
    getBoundingClientRect: () => ({ width: 100, height: 100 }),
  })
  f.map.querySourceFeatures = () => [
    { properties: { id: 7 }, geometry: { type: "Point", coordinates: [5, 5] } },
  ]
  let geometry
  f.map.queryRenderedFeatures = () => [{ properties: { id: 7 }, geometry }]
  const read = () =>
    f.element.dawarichMapSnapshot({ sourceId: "points-mvt-source" }).features[0]
      .screen
  try {
    geometry = {
      type: "MultiLineString",
      coordinates: [
        [
          [-20, -20],
          [-10, -10],
        ],
        [
          [30, 30],
          [40, 40],
        ],
      ],
    }
    assert.deepEqual(read(), { x: 40, y: 40 })
    geometry = {
      type: "MultiPolygon",
      coordinates: [
        [
          [
            [-20, -20],
            [-10, -20],
            [-10, -10],
            [-20, -20],
          ],
        ],
        [
          [
            [30, 30],
            [40, 30],
            [40, 40],
            [30, 30],
          ],
        ],
      ],
    }
    assert.deepEqual(read(), { x: 35, y: 35 })
    geometry = {
      type: "MultiPoint",
      coordinates: [
        [-20, -20],
        [30, 30],
      ],
    }
    assert.deepEqual(read(), { x: 30, y: 30 })
  } finally {
    f.destroy()
  }
})
