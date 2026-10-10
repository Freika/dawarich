import assert from "node:assert/strict"
import { test } from "node:test"
import { readRouteSnapshot } from "../../app-phoenix/assets/js/map/data/route_snapshot.js"
import { RouteSegmenter } from "../../app-phoenix/assets/js/map/algorithms/route_segmenter.js"

const state = {
  revision: 1,
  flightsEnabled: true,
  range: {
    startAt: "2026-03-29T00:00",
    endAt: "2026-03-29T03:00",
    importId: 8,
    timezone: "Europe/Berlin",
  },
}
const points = [
  { id: 1, timestamp: 100, tracker_id: "phone", latitude: 52, longitude: 13 },
  {
    id: 2,
    timestamp: 101,
    tracker_id: "watch",
    latitude: 52.01,
    longitude: 13.01,
  },
  {
    id: 3,
    timestamp: 102,
    tracker_id: "phone",
    latitude: 52.02,
    longitude: 13.02,
  },
]
const flights = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates: [
          [13, 52],
          [14, 53],
        ],
      },
      properties: {
        id: 9,
        departure_time: "1970-01-01T00:01:39Z",
        arrival_time: "1970-01-01T00:01:43Z",
      },
    },
  ],
}

test("exact route snapshot respects import device and profile range", async () => {
  const requests = []
  const reader = {
    async pages(resource, params, options) {
      requests.push({ resource, params, signal: options.signal })
      return points
    },
    async read() {
      return { data: flights }
    },
  }
  const controller = new AbortController()
  const result = await readRouteSnapshot(reader, state, {
    purpose: "poster",
    signal: controller.signal,
    deviceWindows: [{ tracker_id: "phone", start_at: 100, end_at: 102 }],
  })
  assert.deepEqual(requests, [
    {
      resource: "points",
      params: {
        start_at: state.range.startAt,
        end_at: state.range.endAt,
        import_id: 8,
      },
      signal: controller.signal,
    },
  ])
  assert.deepEqual(
    result.points.map((p) => p.id),
    [1, 3],
  )
  assert.equal(result.geojson.features.length, 1)
  assert.equal(result.geojson.features[0].properties.id, 9)
  assert.ok(result.geojson.features[0].geometry.coordinates.length > 2)
  const video = await readRouteSnapshot(reader, state, {
    purpose: "video",
    deviceWindows: [{ tracker_id: "phone", start_at: 100, end_at: 102 }],
  })
  assert.deepEqual(
    video.points.map((p) => p.id),
    [1, 3],
  )
  assert.notEqual(video.geojson.features[0].properties.id, 9)
})

test("route splitting preserves the existing kilometre threshold and device buckets", () => {
  const far = [{ ...points[0] }, { ...points[2], longitude: 14 }]
  assert.equal(
    RouteSegmenter.pointsToRoutes(far, { distanceThresholdMeters: 500 })
      .features.length,
    1,
  )
  assert.equal(
    RouteSegmenter.pointsToRoutes(far, { timeThresholdMinutes: 0.01 }).features
      .length,
    0,
  )
  assert.equal(
    RouteSegmenter.pointsToRoutes(points).features[0].properties.pointCount,
    2,
  )
  const dateLine = [
    { ...points[0], longitude: 179 },
    { ...points[2], longitude: -179 },
  ]
  const feature = RouteSegmenter.pointsToRoutes(dateLine).features[0]
  assert.equal(feature.geometry.type, "MultiLineString")
  assert.equal(feature.geometry.coordinates[0].at(-1)[0], 180)
  assert.equal(feature.geometry.coordinates[1][0][0], -180)
})
