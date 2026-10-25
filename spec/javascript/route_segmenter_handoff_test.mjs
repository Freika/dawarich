import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const flightArcs = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/flight_arcs.js",
    import.meta.url,
  ),
  "utf8",
)
const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/utils/route_segmenter.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(
  '"./flight_arcs"',
  `"data:text/javascript;base64,${Buffer.from(flightArcs).toString("base64")}"`,
)
const { RouteSegmenter } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const point = (tracker_id, timestamp, longitude) => ({
  tracker_id,
  timestamp,
  longitude,
  latitude: -40,
})

const phone = [
  point("phone", 0, -140.002),
  point("phone", 60, -140.0),
  point("phone", 1200, -139.95),
  point("phone", 1260, -139.948),
]

const routeTimes = (points) =>
  RouteSegmenter.pointsToRoutes(points, { timeThresholdMinutes: 60 })
    .features.map((feature) => [
      feature.properties.startTime,
      feature.properties.endTime,
    ])
    .sort((a, b) => a[0] - b[0])

test("cuts a route where another tracker recorded a whole route in its gap", () => {
  const watch = [
    point("watch", 120, -140.0),
    point("watch", 660, -139.975),
    point("watch", 1140, -139.95),
  ]

  assert.deepEqual(routeTimes([...phone, ...watch]), [
    [0, 60],
    [120, 1140],
    [1200, 1260],
  ])
})

test("keeps a route whole when another tracker recorded alongside it", () => {
  const watch = [
    point("watch", 30, -140.001),
    point("watch", 660, -139.975),
    point("watch", 1230, -139.949),
  ]

  assert.deepEqual(routeTimes([...phone, ...watch]), [
    [0, 1260],
    [30, 1230],
  ])
})
