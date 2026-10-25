import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")

const arcsUrl = moduleUrl(await read("maps_maplibre/utils/flight_arcs.js"))
const { RouteSegmenter } = await import(
  moduleUrl(
    (await read("maps_maplibre/utils/route_segmenter.js")).replace(
      '"./flight_arcs"',
      `"${arcsUrl}"`,
    ),
  )
)

const points = (...coords) =>
  coords.map(([longitude, latitude]) => ({ longitude, latitude }))
const latitudes = (lines) => lines.flat().map(([, lat]) => lat)
const MERCATOR_MAX_LATITUDE = 85.0511287798
const toRad = (deg) => (deg * Math.PI) / 180

test("a sparse antimeridian route climbs to its great-circle vertex", () => {
  const lines = RouteSegmenter.unwrapCoordinates(points([160, 70], [-60, 70]))
  const vertex =
    (Math.atan(Math.tan(toRad(70)) / Math.cos(toRad(70))) * 180) / Math.PI

  assert.ok(Math.abs(Math.max(...latitudes(lines)) - vertex) < 0.5)
  assert.ok(Math.min(...latitudes(lines)) >= 70 - 1e-9)
})

test("a route over the pole leaves the Mercator world instead of tracing its edge", () => {
  const lines = RouteSegmenter.unwrapCoordinates(points([20, 80], [-160, 80]))

  assert.ok(latitudes(lines).every((lat) => lat <= MERCATOR_MAX_LATITUDE))
  assert.equal(lines.length, 2)
})

test("a sparse transatlantic route bends north of its endpoints", () => {
  const lines = RouteSegmenter.unwrapCoordinates(
    points([-74, 40.7], [2.35, 48.85]),
  )

  assert.ok(Math.max(...latitudes(lines)) > 51)
})

test("dense GPS points pass through unchanged", () => {
  const coords = [
    [13.4, 52.5],
    [13.401, 52.501],
    [13.402, 52.5015],
  ]

  assert.deepEqual(RouteSegmenter.unwrapCoordinates(points(...coords)), [
    coords,
  ])
})

test("a segment entirely beyond the Mercator edge yields no route", () => {
  const routes = RouteSegmenter.pointsToRoutes([
    { longitude: 10, latitude: 87, timestamp: 0 },
    { longitude: 40, latitude: 88, timestamp: 600 },
  ])

  assert.deepEqual(routes.features, [])
})
